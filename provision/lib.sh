# shellcheck shell=bash
# shellcheck disable=SC2034  # variáveis usadas pelos scripts que fazem source
# lib.sh — funções comuns aos scripts do Jarvis. Uso: source "<caminho>/lib.sh"
# Não ativa `set -e` aqui: cada script decide o próprio modo (todos usam set -euo pipefail).

PROVISION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JARVIS_REPO="${JARVIS_REPO:-$(dirname "$PROVISION_DIR")}"
SYSTEM_DIR="$JARVIS_REPO/system"
# shellcheck source=provision/vars.sh
source "$PROVISION_DIR/vars.sh"

# Padrões de tokens que nunca podem ir para o Git (OpenAI, GitHub, Telegram).
SECRET_RE='(sk-[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|[0-9]{8,10}:AA[A-Za-z0-9_-]{30,})'
# Chaves com nome de segredo e valor literal (não ${VAR}), e chaves privadas PEM. Usar com grep -iE.
SECRET_KEY_RE=$'^[[:space:]]*(api_?key|token|secret|password|passwd|private_key|client_secret)[[:space:]]*:[[:space:]]*[\'"]?[^\'"[:space:]$]{8,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'

JARVIS_CHANGED=${JARVIS_CHANGED:-0}

if [[ -t 1 ]]; then
  C_B=$'\e[1;34m' C_G=$'\e[1;32m' C_Y=$'\e[1;33m' C_R=$'\e[1;31m' C_0=$'\e[0m'
else
  C_B='' C_G='' C_Y='' C_R='' C_0=''
fi
log()  { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
ok()   { printf '%s ok%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s !!%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%sERRO%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "rode com sudo: sudo $0"
}

# apt_get — apt-get que espera o lock do dpkg (numa VPS nova o unattended-upgrades costuma segurá-lo).
apt_get() {
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 "$@"
}

apt_install() {
  apt_get install -y -q "$@"
}

# render MODELO VAR... — imprime o modelo trocando cada @VAR@ pelo valor da variável.
render() {
  local tpl=$1 content var
  shift
  [[ -f $tpl ]] || die "modelo não encontrado: $tpl"
  shopt -u patsub_replacement 2>/dev/null || true   # bash 5.2: '&' no valor fica literal
  content=$(<"$tpl")
  for var in "$@"; do
    [[ -n ${!var+x} ]] || die "variável não definida para o modelo $tpl: $var"
    content=${content//@${var}@/${!var}}
  done
  if grep -qE '@[A-Z][A-Z0-9_]*@' <<<"$content"; then
    die "placeholder sem valor em $tpl: $(grep -oE '@[A-Z][A-Z0-9_]*@' <<<"$content" | sort -u | tr '\n' ' ')"
  fi
  printf '%s\n' "$content"
}

# install_file ORIGEM DESTINO MODO [DONO[:GRUPO]] — copia só se mudou; marca JARVIS_CHANGED=1.
install_file() {
  local src=$1 dst=$2 mode=$3 owner=${4:-}
  [[ -f $src ]] || die "arquivo de origem não encontrado: $src"
  if [[ -f $dst ]] && cmp -s "$src" "$dst"; then
    return 0
  fi
  local args=(-D -m "$mode")
  if [[ -n $owner ]]; then
    args+=(-o "${owner%%:*}" -g "${owner#*:}")
  fi
  install "${args[@]}" "$src" "$dst"
  JARVIS_CHANGED=1
  log "atualizado: $dst"
}

# install_rendered DESTINO MODO DONO MODELO VAR...
install_rendered() {
  local dst=$1 mode=$2 owner=$3 tpl=$4 tmp
  shift 4
  tmp=$(mktemp)
  render "$tpl" "$@" >"$tmp"
  install_file "$tmp" "$dst" "$mode" "$owner"
  rm -f "$tmp"
}

# as_hermes CMD... — roda CMD como o usuário do Hermes, com o ambiente dele.
as_hermes() {
  local uid
  uid=$(id -u "$HERMES_USER")
  local envs=(
    HOME="$HERMES_DIR"
    HERMES_HOME="$HERMES_DIR/.hermes"
    PATH="$HERMES_DIR/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  )
  if [[ -d /run/user/$uid ]]; then
    envs+=(
      XDG_RUNTIME_DIR="/run/user/$uid"
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
      DOCKER_HOST="unix:///run/user/$uid/docker.sock"
    )
  fi
  if [[ $EUID -eq 0 ]]; then
    (cd / && runuser -u "$HERMES_USER" -- env "${envs[@]}" "$@")
  else
    (cd / && sudo -u "$HERMES_USER" env "${envs[@]}" "$@")
  fi
}
