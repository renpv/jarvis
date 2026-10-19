#!/usr/bin/env bash
# 20-wireguard — servidor da VPN (wg0). Os dispositivos são adicionados depois com jarvis-peer.
# Rode:  sudo provision/20-wireguard.sh
set -euo pipefail
# shellcheck source=provision/lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"
preflight os root

apt_install wireguard wireguard-tools qrencode
install -d -m 700 /etc/wireguard /etc/wireguard/clients

if [[ ! -f /etc/wireguard/server.key ]]; then
  log "gerando a chave do servidor"
  (umask 077 && wg genkey >/etc/wireguard/server.key)
fi

if [[ -f /etc/wireguard/$WG_IF.conf ]]; then
  ok "$WG_IF.conf já existe (dispositivos preservados)"
else
  # shellcheck disable=SC2034  # usado pelo render via nome
  WG_SERVER_PRIVKEY=$(cat /etc/wireguard/server.key)
  install_rendered "/etc/wireguard/$WG_IF.conf" 600 root:root "$SYSTEM_DIR/wireguard/wg0.conf.tpl" \
    WG_SERVER_IP WG_PORT WG_SERVER_PRIVKEY
fi

systemctl enable --now "wg-quick@$WG_IF"
ufw allow "$WG_PORT/udp" >/dev/null
install -m 755 "$JARVIS_REPO/bin/jarvis-peer" /usr/local/sbin/jarvis-peer

log "verificando"
wg show "$WG_IF" >/dev/null || die "interface $WG_IF não subiu"
grep -q "inet $WG_SERVER_IP/" <<<"$(ip -4 addr show "$WG_IF")" || die "$WG_IF sem o IP $WG_SERVER_IP"
ok "WireGuard ativo em $WG_SERVER_IP, porta $WG_PORT/udp"
echo "Adicione dispositivos:  sudo jarvis-peer add celular   |   sudo jarvis-peer add notebook"
