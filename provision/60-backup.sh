#!/usr/bin/env bash
# 60-backup — instala o jarvis-backup e o timer diário (03:00). Faz um primeiro backup.
# Rode:  sudo provision/60-backup.sh
set -euo pipefail
# shellcheck source=provision/lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"
require_root

apt_install zstd
install -D -m 644 "$PROVISION_DIR/vars.sh" /etc/jarvis/vars.sh
install -m 755 "$JARVIS_REPO/bin/jarvis-backup" /usr/local/sbin/jarvis-backup
install_file "$SYSTEM_DIR/systemd/jarvis-backup.service" /etc/systemd/system/jarvis-backup.service 644 root:root
install_file "$SYSTEM_DIR/systemd/jarvis-backup.timer" /etc/systemd/system/jarvis-backup.timer 644 root:root
systemctl daemon-reload
systemctl enable --now jarvis-backup.timer

log "primeiro backup"
systemctl start jarvis-backup.service
# shellcheck disable=SC2012  # nomes gerados pelo jarvis-backup
latest=$(ls -1t /var/backups/jarvis/*.tar.zst | head -1)
[[ -n $latest ]] || die "nenhum backup gerado"
# grep lendo de <(...) e não de um pipe: com pipefail, o grep -q pararia cedo e o tar
# levaria SIGPIPE, fazendo um backup bom parecer falho.
grep -q '^\.hermes/' < <(tar -I zstd -tf "$latest") || die "backup sem .hermes/"
ok "backup em $latest; próximo: $(systemctl show jarvis-backup.timer -p NextElapseUSecRealtime --value)"
