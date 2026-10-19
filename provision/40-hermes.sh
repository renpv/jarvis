#!/usr/bin/env bash
# 40-hermes — usuário hermes, instalação do Hermes Agent, .env e serviços systemd.
# Os serviços ficam habilitados mas NÃO são iniciados aqui: o primeiro start é o `jarvis apply`.
# Rode:  sudo provision/40-hermes.sh   (rode de novo depois de preencher o .env)
set -euo pipefail
# shellcheck source=provision/lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"
preflight os root

apt_install git curl xz-utils ca-certificates gh ripgrep jq sqlite3 zstd

if ! id "$HERMES_USER" &>/dev/null; then
  log "criando usuário de sistema $HERMES_USER"
  useradd --system --create-home --home-dir "$HERMES_DIR" --shell /bin/bash "$HERMES_USER"
fi
usermod -aG systemd-journal "$HERMES_USER"   # pode ler logs para monitorar serviços
chmod 750 "$HERMES_DIR"   # a própria home: o hermes não consegue trocá-la por um link
# Dentro da home do hermes, tudo é feito COMO hermes: um link plantado ali não vira acesso de root.
as_hermes mkdir -p "$HERMES_DIR/workspace" "$HERMES_DIR/apps" "$HERMES_DIR/notas" "$HERMES_DIR/.hermes"
as_hermes chmod 750 "$HERMES_DIR/workspace" "$HERMES_DIR/apps" "$HERMES_DIR/notas"
as_hermes chmod 700 "$HERMES_DIR/.hermes"
# Estado do comando jarvis (cópia do último apply/import): do admin, que é quem roda o jarvis.
install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" /var/lib/jarvis

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
if as_hermes test -L "$envf"; then die "$envf é um link simbólico — investigue antes de continuar"; fi
if ! as_hermes grep -qs '^# jarvis:env' "$envf"; then
  if as_hermes test -f "$envf"; then
    as_hermes mv "$envf" "$envf.instalador"
    warn "o .env criado pelo instalador foi guardado em $envf.instalador (para consulta)"
  fi
  # shellcheck disable=SC2016  # $1 expande no sh do hermes, de propósito
  as_hermes sh -c 'umask 077 && cat > "$1"' _ "$envf" <"$JARVIS_REPO/.env.example"
fi
as_hermes chmod 600 "$envf"

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
  warn "preencha o .env:  sudo -u $HERMES_USER nano $envf   — depois rode este script de novo"
fi
