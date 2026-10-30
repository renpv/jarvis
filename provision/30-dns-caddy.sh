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
  # Da receita oficial só precisamos de gnupg e curl: a chave do repositório vem pelo curl abaixo.
  apt_install gnupg curl
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

# Portão do Chatwoot (/installation e /super_admin): credencial própria e aleatória, que o Renato lê
# com `sudo cat /etc/caddy/chatwoot-portao.txt`. Gerada uma vez, acrescentada ao secrets.env.
if ! grep -q '^CHATWOOT_GATE_HASH=' /etc/caddy/secrets.env; then
  senha=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)
  hash=$(caddy hash-password --plaintext "$senha")
  [[ $hash == \$2* ]] || die "não consegui gerar o hash da senha do portão do Chatwoot"
  (umask 077 && printf "CHATWOOT_GATE_USER='%s'\nCHATWOOT_GATE_HASH='%s'\n" "$ADMIN_USER" "$hash" >>/etc/caddy/secrets.env)
  (umask 077 && printf 'usuário: %s\nsenha: %s\n' "$ADMIN_USER" "$senha" >/etc/caddy/chatwoot-portao.txt)
  unset senha
  log "portão do Chatwoot criado: sudo cat /etc/caddy/chatwoot-portao.txt"
fi

install -d -m 755 /etc/caddy/apps.d
# Apps publicados antes do Chatwoot dependiam do default_bind global, que saiu: põe o bind da VPN.
for f in /etc/caddy/apps.d/*.caddy; do
  [[ -f $f ]] || continue
  if ! grep -qE '^[[:space:]]+bind ' "$f"; then
    sed -i "1a\\\tbind $WG_SERVER_IP" "$f"
    log "bind da VPN acrescentado em $f"
  fi
done
PUBLIC_IP=$(ip_publico)
_is_ipv4 "$PUBLIC_IP" || die "não consegui descobrir o IP público; defina PUBLIC_IP em vars.sh"
# No CI, certificado interno: tentar o Let's Encrypt a partir do runner gastaria o limite de
# falhas de validação do domínio real.
# shellcheck disable=SC2034  # usado pelo render via nome
CHATWOOT_TLS=""
# shellcheck disable=SC2034
if [[ ${JARVIS_CI:-} == 1 ]]; then CHATWOOT_TLS="tls internal"; fi
install_rendered /etc/caddy/Caddyfile 644 root:root "$SYSTEM_DIR/caddy/Caddyfile.tpl" \
  WG_SERVER_IP DOMAIN DASHBOARD_PORT PUBLIC_IP CHATWOOT_DOMAIN CHATWOOT_PORT CHATWOOT_TLS
install_rendered /etc/systemd/system/caddy.service.d/jarvis.conf 644 root:root \
  "$SYSTEM_DIR/systemd/caddy-override.conf.tpl" WG_IF
# shellcheck disable=SC1091  # arquivo só existe na VPS
(set -a && . /etc/caddy/secrets.env && caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile) >/dev/null ||
  die "Caddyfile inválido (rode o validate à mão para ver o erro)"
systemctl daemon-reload
systemctl enable caddy
systemctl restart caddy

log "firewall: DNS e HTTP da VPN; 80/443 públicos só para o Chatwoot"
ufw allow in on "$WG_IF" to "$WG_SERVER_IP" port 53 >/dev/null
ufw allow in on "$WG_IF" to "$WG_SERVER_IP" port 80 proto tcp >/dev/null
ufw allow to "$PUBLIC_IP" port 80,443 proto tcp >/dev/null

log "verificando"
[[ $(dig +short @"$WG_SERVER_IP" "hermes.$DOMAIN") == "$WG_SERVER_IP" ]] || die "DNS não resolve hermes.$DOMAIN"
[[ -n $(dig +short @"$WG_SERVER_IP" github.com) ]] || die "DNS não encaminha nomes externos"
code=$(curl -s -o /dev/null -w '%{http_code}' --resolve "hermes.$DOMAIN:80:$WG_SERVER_IP" "http://hermes.$DOMAIN/")
[[ $code == 401 ]] || die "esperava 401 (pedido de senha) do Caddy, veio $code"
fora=$(ss -Htln '( sport = :80 or sport = :443 )' | awk '{print $4}' | grep -vE "^($WG_SERVER_IP|$PUBLIC_IP):" || true)
[[ -z $fora ]] || die "algo escuta em 80/443 fora da VPN e do IP público: $fora"
code=$(curl -s -o /dev/null -w '%{http_code}' --resolve "hermes.$DOMAIN:80:$PUBLIC_IP" "http://hermes.$DOMAIN/" || true)
[[ $code == 000 || $code == 308 || $code == 404 ]] || die "o dashboard respondeu ($code) pelo IP público"
ok "DNS e dashboard só na VPN; Caddy público só para $CHATWOOT_DOMAIN ($PUBLIC_IP)"
