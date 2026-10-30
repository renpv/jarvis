#!/usr/bin/env bash
# 70-chatwoot — Chatwoot (atendimento) no Docker rootless do usuário chatwoot, atrás do Caddy público.
# Design: docs/specs/2026-10-30-chatwoot-design.md. Guia: docs/aprendizado/90-chatwoot.md.
# Rode:  sudo provision/70-chatwoot.sh   (de novo a cada troca de versão no compose.yaml)
set -euo pipefail
# shellcheck source=provision/lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"
# Depende do 50 (pacotes do Docker rootless, perfil AppArmor) e do 30 (Caddy com o site público).
preflight os root "user:$HERMES_USER" user:caddy cmd:dockerd-rootless-setuptool.sh cmd:caddy cmd:openssl cmd:nft

U=$CHATWOOT_USER
D=$CHATWOOT_DIR
como() { as_usuario "$U" "$D" "$@"; }

if ! id "$U" &>/dev/null; then
  log "criando usuário de sistema $U"
  useradd --system --create-home --home-dir "$D" --shell /usr/sbin/nologin "$U"
fi
chmod 750 "$D"
# Faixa de IDs própria (a do hermes é 300000–365535): containers dos dois nunca compartilham UID.
if ! grep -q "^$U:" /etc/subuid; then
  usermod --add-subuids 400000-465535 --add-subgids 400000-465535 "$U"
fi
loginctl enable-linger "$U"
uid=$(id -u "$U")
for _ in $(seq 1 20); do
  if [[ -S /run/user/$uid/bus ]]; then break; fi
  sleep 0.5
done
[[ -S /run/user/$uid/bus ]] || die "a sessão systemd do usuário $U não subiu"

if [[ ! -f $D/.config/systemd/user/docker.service ]]; then
  log "configurando o Docker rootless do $U"
  como dockerd-rootless-setuptool.sh install >/dev/null || die "falha ao configurar o Docker rootless do $U"
fi
como systemctl --user enable --now docker >/dev/null 2>&1 || die "falha ao iniciar o Docker rootless do $U"

log "porta local só para o Caddy (nftables)"
# shellcheck disable=SC2034  # usados pelo render via nome
CADDY_UID=$(id -u caddy) CHATWOOT_UID=$uid
install_rendered /etc/jarvis/chatwoot-porta.nft 644 root:root "$SYSTEM_DIR/nftables/chatwoot-porta.nft.tpl" \
  CHATWOOT_PORT CADDY_UID CHATWOOT_UID
install_file "$SYSTEM_DIR/systemd/jarvis-chatwoot-porta.service" /etc/systemd/system/jarvis-chatwoot-porta.service 644 root:root
systemctl daemon-reload
systemctl enable jarvis-chatwoot-porta.service >/dev/null 2>&1
# reload, nunca restart: a troca da regra é atômica e a porta não fica aberta nem por um instante.
if systemctl is-active --quiet jarvis-chatwoot-porta.service; then
  systemctl reload jarvis-chatwoot-porta.service
else
  systemctl start jarvis-chatwoot-porta.service
fi
nft list table inet jarvis_chatwoot >/dev/null || die "regra da porta do Chatwoot não carregou"

log "compose e .env"
# Tudo dentro da home do chatwoot é gravado COMO chatwoot: um link plantado ali não vira acesso de root.
if como test -L "$D/.env" || como test -L "$D/compose.yaml"; then die "link simbólico em $D — investigue"; fi
# shellcheck disable=SC2016  # $1 expande no sh do chatwoot, de propósito
como sh -c 'cat > "$1"' _ "$D/compose.yaml" <"$SYSTEM_DIR/chatwoot/compose.yaml"
envtmp=$(mktemp)
trap 'rm -f "$envtmp"' EXIT
como cat "$D/.env" >"$envtmp" 2>/dev/null || true
segredo() { openssl rand -hex "$1"; }
# Do vars.sh, sempre atualizados (não são segredo):
sed -i -E '/^(CHATWOOT_DOMAIN|CHATWOOT_PORT)=/d' "$envtmp"
printf 'CHATWOOT_DOMAIN=%s\nCHATWOOT_PORT=%s\n' "$CHATWOOT_DOMAIN" "$CHATWOOT_PORT" >>"$envtmp"
# Gerados uma vez; nunca trocados (trocar o SECRET_KEY_BASE desloga todos; o do banco quebraria o acesso):
env_garantir "$envtmp" SECRET_KEY_BASE "$(segredo 64)"
env_garantir "$envtmp" POSTGRES_PASSWORD "$(segredo 24)"
env_garantir "$envtmp" REDIS_PASSWORD "$(segredo 24)"
env_garantir "$envtmp" FB_VERIFY_TOKEN "$(segredo 16)"
env_garantir "$envtmp" IG_VERIFY_TOKEN "$(segredo 16)"
# Preenchidos pelo Renato quando criar o app do Meta e o SMTP (guia 90):
for k in FB_APP_ID FB_APP_SECRET MAILER_SENDER_EMAIL SMTP_ADDRESS SMTP_PORT SMTP_USERNAME SMTP_PASSWORD; do
  env_garantir "$envtmp" "$k" ""
done
# shellcheck disable=SC2016
como sh -c 'umask 077 && cat > "$1" && chmod 600 "$1"' _ "$D/.env" <"$envtmp"

# shellcheck disable=SC2016  # $1/$@ expandem no sh do chatwoot
compose() { como sh -c 'cd "$1" && shift && docker compose "$@"' _ "$D" "$@"; }
compose config -q || die "compose.yaml inválido"

if [[ ${JARVIS_CI:-} == 1 ]]; then
  # As imagens somam mais de 1 GB e o Chatwoot pede ~4 GB de RAM: o CI valida a montagem, não sobe.
  como touch "$D/.ci-sem-containers"   # o jarvis-backup não tenta o dump de um banco que não subiu
  ok "modo CI: compose validado; Chatwoot não iniciado"
  exit 0
fi

log "imagens (podem demorar na primeira vez)"
compose pull -q
log "banco: db:chatwoot_prepare (cria na primeira vez, migra nas atualizações)"
compose up -d postgres redis
compose run --rm rails bundle exec rails db:chatwoot_prepare >/dev/null
compose up -d --remove-orphans

log "verificando"
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null "http://127.0.0.1:$CHATWOOT_PORT/api"; then break; fi
  sleep 3
done
curl -fsS -o /dev/null "http://127.0.0.1:$CHATWOOT_PORT/api" || die "o Chatwoot não respondeu em 127.0.0.1:$CHATWOOT_PORT (veja: $0 com 'compose logs rails')"
fora=$(ss -Htln "sport = :$CHATWOOT_PORT" | awk '{print $4}' | grep -v '^127\.0\.0\.1:' || true)
[[ -z $fora ]] || die "a porta $CHATWOOT_PORT escuta fora do loopback: $fora"
ok "Chatwoot ativo: https://$CHATWOOT_DOMAIN"
echo "   Primeiro acesso: https://$CHATWOOT_DOMAIN/installation/onboarding (usuário e senha: sudo cat /etc/caddy/chatwoot-portao.txt)"
