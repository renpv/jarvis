#!/usr/bin/env bash
# 40-hermes — usuário hermes, instalação do Hermes Agent, .env e serviços systemd.
# Os serviços ficam habilitados mas NÃO são iniciados aqui: o primeiro start é o `jarvis apply`.
# Rode:  sudo provision/40-hermes.sh   (rode de novo depois de preencher o .env)
set -euo pipefail
# shellcheck source=provision/lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"
require_root

apt_install git curl xz-utils ca-certificates gh ripgrep jq sqlite3 zstd

if ! id "$HERMES_USER" &>/dev/null; then
  log "criando usuário de sistema $HERMES_USER"
  useradd --system --create-home --home-dir "$HERMES_DIR" --shell /bin/bash "$HERMES_USER"
fi
usermod -aG systemd-journal "$HERMES_USER"   # pode ler logs para monitorar serviços
chmod 750 "$HERMES_DIR"
for d in workspace apps notas; do
  install -d -m 750 -o "$HERMES_USER" -g "$HERMES_USER" "$HERMES_DIR/$d"
done
install -d -m 700 /var/lib/jarvis

HB="$HERMES_DIR/.local/bin/hermes"
if [[ ! -x $HB ]]; then
  log "instalando o Hermes Agent como $HERMES_USER"
  as_hermes bash -c 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive'
fi
as_hermes "$HB" --version || die "o comando hermes não respondeu"

as_hermes git config --global user.name "Jarvis"
as_hermes git config --global user.email "jarvis@$(hostname)"

log ".env"
envf="$HERMES_DIR/.hermes/.env"
install -d -m 700 -o "$HERMES_USER" -g "$HERMES_USER" "$HERMES_DIR/.hermes"
if ! grep -qs '^# jarvis:env' "$envf"; then
  if [[ -f $envf ]]; then
    mv "$envf" "$envf.instalador"
    warn "o .env criado pelo instalador foi guardado em $envf.instalador (para consulta)"
  fi
  install -m 600 -o "$HERMES_USER" -g "$HERMES_USER" "$JARVIS_REPO/.env.example" "$envf"
fi
chmod 600 "$envf"

log "serviços systemd"
# shellcheck disable=SC2034  # usado pelo render via nome
HERMES_UID=$(id -u "$HERMES_USER")
install_rendered /etc/systemd/system/hermes-gateway.service 644 root:root \
  "$SYSTEM_DIR/systemd/hermes-gateway.service.tpl" HERMES_USER HERMES_DIR HERMES_UID
install_rendered /etc/systemd/system/hermes-dashboard.service 644 root:root \
  "$SYSTEM_DIR/systemd/hermes-dashboard.service.tpl" HERMES_USER HERMES_DIR HERMES_UID DASHBOARD_PORT
loginctl enable-linger "$HERMES_USER"   # cria /run/user/UID e mantém a sessão do hermes no boot
systemctl daemon-reload
systemctl enable hermes-gateway hermes-dashboard

if "$JARVIS_REPO/bin/jarvis" check-env; then
  ok "Hermes instalado. Próximo: 'jarvis import' (primeira vez) — veja docs/aprendizado/40-hermes.md"
else
  warn "preencha o .env:  sudo nano $envf   — depois rode este script de novo"
fi
