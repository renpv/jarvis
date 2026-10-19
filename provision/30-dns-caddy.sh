#!/usr/bin/env bash
# 30-dns-caddy — DNS interno (*.jarvis.lan) e Caddy, ambos escutando só no IP da VPN.
# Pede a senha do dashboard na primeira vez. Rode:  sudo provision/30-dns-caddy.sh
set -euo pipefail
# shellcheck source=provision/lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"
preflight os root "iface:$WG_IF" ci-env:JARVIS_DASHBOARD_PASSWORD

log "dnsmasq"
# A configuração entra ANTES do pacote: assim o dnsmasq já sobe sem brigar com o systemd-resolved.
install_rendered /etc/dnsmasq.d/jarvis.conf 644 root:root "$SYSTEM_DIR/dnsmasq/jarvis.conf.tpl" WG_SERVER_IP DOMAIN
install_rendered /etc/systemd/system/dnsmasq.service.d/jarvis.conf 644 root:root \
  "$SYSTEM_DIR/systemd/dnsmasq-override.conf.tpl" WG_IF
apt_install dnsmasq dnsutils
systemctl daemon-reload
systemctl enable dnsmasq
systemctl restart dnsmasq

log "Caddy (repositório oficial)"
if ! command -v caddy >/dev/null; then
  apt_install debian-keyring debian-archive-keyring apt-transport-https gnupg curl
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key |
    gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt >/etc/apt/sources.list.d/caddy-stable.list
  apt_get update -q
  apt_install caddy
fi

if [[ ! -f /etc/caddy/secrets.env ]]; then
  if [[ ${JARVIS_CI:-} == 1 ]]; then
    hash=$(caddy hash-password --plaintext "$JARVIS_DASHBOARD_PASSWORD")
  else
    log "crie a senha do dashboard (usuário: $ADMIN_USER). Ela não aparece na tela."
    hash=$(caddy hash-password)
  fi
  [[ $hash == \$2* ]] || die "não consegui gerar o hash da senha"
  (umask 077 && printf "DASHBOARD_USER='%s'\nDASHBOARD_HASH='%s'\n" "$ADMIN_USER" "$hash" >/etc/caddy/secrets.env)
fi

install -d -m 755 /etc/caddy/apps.d
install_rendered /etc/caddy/Caddyfile 644 root:root "$SYSTEM_DIR/caddy/Caddyfile.tpl" WG_SERVER_IP DOMAIN DASHBOARD_PORT
install_rendered /etc/systemd/system/caddy.service.d/jarvis.conf 644 root:root \
  "$SYSTEM_DIR/systemd/caddy-override.conf.tpl" WG_IF
# shellcheck disable=SC1091  # arquivo só existe na VPS
(set -a && . /etc/caddy/secrets.env && caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile) >/dev/null ||
  die "Caddyfile inválido (rode o validate à mão para ver o erro)"
systemctl daemon-reload
systemctl enable caddy
systemctl restart caddy

log "firewall: DNS e HTTP só pela VPN"
ufw allow in on "$WG_IF" to "$WG_SERVER_IP" port 53 >/dev/null
ufw allow in on "$WG_IF" to "$WG_SERVER_IP" port 80 proto tcp >/dev/null

log "verificando"
[[ $(dig +short @"$WG_SERVER_IP" "hermes.$DOMAIN") == "$WG_SERVER_IP" ]] || die "DNS não resolve hermes.$DOMAIN"
[[ -n $(dig +short @"$WG_SERVER_IP" github.com) ]] || die "DNS não encaminha nomes externos"
code=$(curl -s -o /dev/null -w '%{http_code}' --resolve "hermes.$DOMAIN:80:$WG_SERVER_IP" "http://hermes.$DOMAIN/")
[[ $code == 401 ]] || die "esperava 401 (pedido de senha) do Caddy, veio $code"
if ss -Htln 'sport = :80' | awk '{print $4}' | grep -qv "^$WG_SERVER_IP:"; then
  die "algo escuta na porta 80 fora do IP da VPN"
fi
ok "DNS e Caddy ativos só na VPN"
