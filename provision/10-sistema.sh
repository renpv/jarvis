#!/usr/bin/env bash
# 10-sistema — fuso, atualizações de segurança automáticas, firewall, fail2ban e SSH endurecido.
# Rode como o admin:  sudo provision/10-sistema.sh
set -euo pipefail
# shellcheck source=provision/lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"
preflight os root sudo-admin admin-keys

log "fuso horário: $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"

log "pacotes"
apt_install ufw fail2ban python3-systemd unattended-upgrades

install_file "$SYSTEM_DIR/apt/20auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades 644 root:root

JARVIS_CHANGED=0
install_file "$SYSTEM_DIR/fail2ban/jail.local" /etc/fail2ban/jail.local 644 root:root
systemctl enable --now fail2ban
if ((JARVIS_CHANGED)); then systemctl restart fail2ban; fi

log "firewall (ufw): entrada bloqueada, exceto SSH"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow OpenSSH >/dev/null
ufw --force enable >/dev/null

log "SSH: sem root, sem senha, só $ADMIN_USER"
JARVIS_CHANGED=0
install_rendered /etc/ssh/sshd_config.d/00-jarvis.conf 644 root:root "$SYSTEM_DIR/ssh/00-jarvis.conf.tpl" ADMIN_USER
install -d -m 755 /run/sshd
if ! sshd -t; then
  rm -f /etc/ssh/sshd_config.d/00-jarvis.conf
  die "configuração SSH inválida; arquivo removido, nada mudou"
fi
if ((JARVIS_CHANGED)); then systemctl try-reload-or-restart ssh; fi

log "verificando"
sshd -T | grep -qx 'permitrootlogin no' || die "PermitRootLogin não está 'no'"
sshd -T | grep -qx 'passwordauthentication no' || die "PasswordAuthentication não está 'no'"
ufw status | grep -q 'Status: active' || die "ufw inativo"
systemctl is-active --quiet fail2ban || die "fail2ban inativo"
[[ $(timedatectl show -p Timezone --value) == "$TIMEZONE" ]] || die "fuso não aplicado"
ok "sistema pronto. Confirme em OUTRO terminal que 'ssh $ADMIN_USER@IP' funciona e 'ssh root@IP' é recusado."
