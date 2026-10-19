#!/usr/bin/env bash
# 50-docker-rootless — Docker sem root para o hermes, jarvis-expose e sudoers restrito.
# Rode:  sudo provision/50-docker-rootless.sh
set -euo pipefail
# shellcheck source=provision/lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"
preflight os root "user:$HERMES_USER"

log "Docker (repositório oficial)"
# Se o repositório do Docker já estiver configurado (ex.: runner do CI), só completa os pacotes.
if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091  # arquivo do sistema
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
    >/etc/apt/sources.list.d/docker.list
  apt_get update -q
fi
# slirp4netns (rede) e dbus-user-session (systemctl --user) explícitos: alguns ambientes não instalam "Recommends".
apt_install docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras docker-compose-plugin uidmap slirp4netns dbus-user-session

# Ubuntu 24.04 restringe user namespaces sem privilégio; o rootlesskit precisa de um perfil AppArmor.
if [[ -d /etc/apparmor.d ]] && ! grep -rqs rootlesskit /etc/apparmor.d; then
  cat >/etc/apparmor.d/usr.bin.rootlesskit <<'EOF'
abi <abi/4.0>,
include <tunables/global>

"/usr/bin/rootlesskit" flags=(unconfined) {
  userns,

  include if exists <local/usr.bin.rootlesskit>
}
EOF
  apparmor_parser -r /etc/apparmor.d/usr.bin.rootlesskit
fi

# Sem o Docker de root: só o rootless do hermes.
systemctl disable --now docker.service docker.socket containerd.service 2>/dev/null || true

uid=$(id -u "$HERMES_USER")
if ! grep -q "^$HERMES_USER:" /etc/subuid; then
  usermod --add-subuids 300000-365535 --add-subgids 300000-365535 "$HERMES_USER"
fi
loginctl enable-linger "$HERMES_USER"
for _ in $(seq 1 20); do
  if [[ -S /run/user/$uid/bus ]]; then break; fi
  sleep 0.5
done
[[ -S /run/user/$uid/bus ]] || die "a sessão systemd do usuário $HERMES_USER não subiu"

docker_log() {
  warn "o Docker rootless do $HERMES_USER não subiu; diagnóstico:"
  {
    id "$HERMES_USER"
    loginctl show-user "$HERMES_USER" -p UID -p RuntimePath -p Linger -p State || true
    ls -ld /run/user/* || true
    echo "--- ambiente da sessão systemd do $HERMES_USER:"
    as_hermes systemctl --user show-environment || true
    echo "--- journal do docker.service (usuário):"
    as_hermes journalctl --user --unit docker.service -n 40 --no-pager || true
  } >&2
}
if [[ ! -f $HERMES_DIR/.config/systemd/user/docker.service ]]; then
  log "configurando o Docker rootless do $HERMES_USER"
  as_hermes dockerd-rootless-setuptool.sh install || { docker_log; die "falha ao configurar o Docker rootless"; }
fi
as_hermes systemctl --user enable --now docker || { docker_log; die "falha ao iniciar o Docker rootless"; }

log "jarvis-expose e sudoers"
install -m 755 "$JARVIS_REPO/bin/jarvis-expose" /usr/local/sbin/jarvis-expose
ln -sfn /usr/local/sbin/jarvis-expose /usr/local/sbin/jarvis-unexpose
tmp=$(mktemp)
render "$SYSTEM_DIR/sudoers/hermes.tpl" HERMES_USER >"$tmp"
visudo -cf "$tmp" >/dev/null || die "sudoers gerado é inválido"
install_file "$tmp" /etc/sudoers.d/hermes 440 root:root
rm -f "$tmp"

systemctl try-restart hermes-gateway hermes-dashboard

log "verificando"
as_hermes docker run --rm hello-world >/dev/null || die "Docker rootless não executa containers"
if as_hermes sudo -n /usr/bin/true 2>/dev/null; then die "hermes tem sudo além do permitido!"; fi
if as_hermes ls "$JARVIS_DIR" >/dev/null 2>&1; then die "hermes consegue ler $JARVIS_DIR!"; fi
if as_hermes sudo -n /usr/local/sbin/jarvis-expose ../x 8100 2>/dev/null; then die "jarvis-expose aceitou nome inválido!"; fi
ok "Docker rootless ativo; hermes só tem sudo para jarvis-expose/unexpose"
