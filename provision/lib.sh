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

# ── Preflight: valida tudo ANTES de alterar a máquina ─────────────────────────

_is_port() { [[ $1 =~ ^[1-9][0-9]{0,4}$ ]] && (($1 <= 65535)); }
_is_octet() { [[ $1 =~ ^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$ ]]; }
_is_ipv4() {
  [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  local IFS=. o
  for o in $1; do _is_octet "$o" || return 1; done
}
# O último rótulo (TLD) começa com letra: "203.0.113" não é nome DNS.
_is_dns() { [[ $1 =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; }
_is_user() { [[ $1 =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
_is_abspath() { [[ $1 == /* && $1 != *..* && $1 != *[[:space:]]* ]]; }

# check_vars — valida o vars.sh. Imprime um problema por linha; retorna 1 se houver algum.
check_vars() {
  local e=() p
  _is_user "$ADMIN_USER" || e+=("ADMIN_USER inválido: '$ADMIN_USER' (minúsculas, números, _ e -)")
  _is_user "$HERMES_USER" || e+=("HERMES_USER inválido: '$HERMES_USER'")
  [[ $ADMIN_USER != "$HERMES_USER" ]] || e+=("ADMIN_USER e HERMES_USER precisam ser diferentes")
  [[ $ADMIN_USER != root && $HERMES_USER != root ]] || e+=("ADMIN_USER/HERMES_USER não podem ser root")
  _is_abspath "$HERMES_DIR" || e+=("HERMES_DIR precisa ser caminho absoluto, sem '..' e sem espaço: '$HERMES_DIR'")
  _is_abspath "$JARVIS_DIR" || e+=("JARVIS_DIR precisa ser caminho absoluto, sem '..' e sem espaço: '$JARVIS_DIR'")
  [[ $GITHUB_SLUG =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || e+=("GITHUB_SLUG precisa ser dono/repo: '$GITHUB_SLUG'")
  [[ $GITHUB_REPO == git@github.com:* || $GITHUB_REPO == https://github.com/* ]] ||
    e+=("GITHUB_REPO precisa ser do github.com: '$GITHUB_REPO'")
  [[ -n $TIMEZONE && $TIMEZONE != *..* && -f ${ZONEINFO_DIR:-/usr/share/zoneinfo}/$TIMEZONE ]] ||
    e+=("TIMEZONE inexistente: '$TIMEZONE' (veja timedatectl list-timezones)")
  _is_dns "$DOMAIN" || e+=("DOMAIN inválido: '$DOMAIN' (minúsculas, com pelo menos um ponto)")
  [[ $WG_IF =~ ^[a-z][a-z0-9]{0,14}$ ]] || e+=("WG_IF inválido: '$WG_IF'")
  for p in WG_PORT DASHBOARD_PORT APP_PORT_MIN APP_PORT_MAX; do
    _is_port "${!p}" || e+=("$p inválida: '${!p}' (inteiro de 1 a 65535)")
  done
  if _is_port "$APP_PORT_MIN" && _is_port "$APP_PORT_MAX"; then
    ((APP_PORT_MIN < APP_PORT_MAX)) || e+=("APP_PORT_MIN ($APP_PORT_MIN) precisa ser menor que APP_PORT_MAX ($APP_PORT_MAX)")
    if _is_port "$DASHBOARD_PORT" && ((DASHBOARD_PORT >= APP_PORT_MIN && DASHBOARD_PORT <= APP_PORT_MAX)); then
      e+=("DASHBOARD_PORT ($DASHBOARD_PORT) não pode cair na faixa de apps $APP_PORT_MIN–$APP_PORT_MAX")
    fi
  fi
  _is_ipv4 "$WG_NET.0" || e+=("WG_NET inválida: '$WG_NET' (três octetos, ex.: 10.8.0)")
  if _is_ipv4 "$WG_SERVER_IP"; then
    [[ ${WG_SERVER_IP%.*} == "$WG_NET" ]] || e+=("WG_SERVER_IP ($WG_SERVER_IP) fora da rede $WG_NET.0/24")
  else
    e+=("WG_SERVER_IP inválido: '$WG_SERVER_IP'")
  fi
  if [[ -n $WG_ENDPOINT ]] && ! _is_ipv4 "$WG_ENDPOINT" && ! _is_dns "$WG_ENDPOINT"; then
    e+=("WG_ENDPOINT inválido: '$WG_ENDPOINT' (vazio, IPv4 ou nome DNS)")
  fi
  ((${#e[@]} == 0)) && return 0
  printf '%s\n' "${e[@]}"
  return 1
}

# check_os — Ubuntu 24.04?
check_os() {
  local f=${OS_RELEASE:-/etc/os-release}
  [[ -r $f ]] || return 1
  # shellcheck disable=SC1090  # arquivo do sistema (ou de teste)
  (. "$f" && [[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 24.04 ]])
}

# preflight [REQUISITO...] — valida variáveis e requisitos; se houver problema, lista TODOS e sai.
preflight() {
  local errs=() out r v h
  if ! out=$(check_vars); then mapfile -t errs <<<"$out"; fi
  for r in "$@"; do
    case $r in
      os) check_os || errs+=("sistema: este script precisa de Ubuntu 24.04") ;;
      root) [[ $EUID -eq 0 ]] || errs+=("rode com sudo: sudo $0") ;;
      sudo-admin) [[ ${SUDO_USER:-} == "$ADMIN_USER" ]] || errs+=("rode como $ADMIN_USER usando sudo (não como root direto)") ;;
      admin-keys)
        h=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
        [[ -n $h && -s $h/.ssh/authorized_keys ]] ||
          errs+=("$ADMIN_USER sem authorized_keys: endurecer o SSH agora trancaria você para fora")
        ;;
      cmd:*) command -v "${r#cmd:}" >/dev/null || errs+=("comando ausente: ${r#cmd:}") ;;
      ci-env:*)
        v=${r#ci-env:}
        if [[ ${JARVIS_CI:-} == 1 && -z ${!v:-} ]]; then errs+=("modo CI: defina $v"); fi
        ;;
      iface:*)
        ip -4 addr show "${r#iface:}" 2>/dev/null | grep -q "inet $WG_SERVER_IP/" ||
          errs+=("interface ${r#iface:} sem o IP $WG_SERVER_IP (rode 20-wireguard.sh antes)")
        ;;
      user:*) id "${r#user:}" &>/dev/null || errs+=("usuário inexistente: ${r#user:}") ;;
      *) errs+=("requisito desconhecido no preflight: $r") ;;
    esac
  done
  ((${#errs[@]} == 0)) && return 0
  printf '%sERRO%s preflight encontrou %d problema(s) — nada foi alterado:\n' "$C_R" "$C_0" "${#errs[@]}" >&2
  printf '  - %s\n' "${errs[@]}" >&2
  exit 1
}
