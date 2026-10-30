# shellcheck shell=bash
# shellcheck disable=SC2034
# vars.sh — variáveis NÃO secretas do Jarvis. Fonte única: scripts e ferramentas leem daqui.
# Na VPS, uma cópia fica em /etc/jarvis/vars.sh para as ferramentas de root.
# Todas aceitam sobrescrita pelo ambiente (útil nos testes).

ADMIN_USER=${ADMIN_USER:-renpv}                 # seu usuário na VPS (com sudo)
HERMES_USER=${HERMES_USER:-hermes}              # usuário de sistema que roda o Hermes
HERMES_DIR=${HERMES_DIR:-/var/lib/hermes}       # home do hermes
JARVIS_DIR=${JARVIS_DIR:-/opt/jarvis}           # clone deste repo na VPS
GITHUB_SLUG=${GITHUB_SLUG:-renpv/jarvis}
GITHUB_REPO=${GITHUB_REPO:-git@github.com:$GITHUB_SLUG.git}
TIMEZONE=${TIMEZONE:-America/Fortaleza}

DOMAIN=${DOMAIN:-jarvis.lan}                    # nomes internos: hermes.jarvis.lan, <app>.jarvis.lan
WG_IF=${WG_IF:-wg0}
WG_PORT=${WG_PORT:-51820}
WG_NET=${WG_NET:-10.8.0}                        # rede 10.8.0.0/24
WG_SERVER_IP=${WG_SERVER_IP:-10.8.0.1}
WG_ENDPOINT=${WG_ENDPOINT:-}                    # vazio = descobre o IP público sozinho

DASHBOARD_PORT=${DASHBOARD_PORT:-9119}
APP_PORT_MIN=${APP_PORT_MIN:-8100}
APP_PORT_MAX=${APP_PORT_MAX:-8199}

# Chatwoot (atendimento público: único serviço da VPS fora da VPN — docs/specs/2026-10-30-chatwoot-design.md)
CHATWOOT_USER=${CHATWOOT_USER:-chatwoot}        # usuário de sistema com Docker rootless próprio
CHATWOOT_DIR=${CHATWOOT_DIR:-/var/lib/chatwoot} # home: .env, compose.yaml, storage, postgres, redis
CHATWOOT_DOMAIN=${CHATWOOT_DOMAIN:-atendimento.renpv.com.br}
CHATWOOT_PORT=${CHATWOOT_PORT:-3000}            # o Rails escuta só em 127.0.0.1; o Caddy publica
PUBLIC_IP=${PUBLIC_IP:-}                        # vazio = descobre pela rota padrão
