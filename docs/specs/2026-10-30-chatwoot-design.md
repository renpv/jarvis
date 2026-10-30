# Chatwoot na VPS do Jarvis — design

Data: 2026-10-30. Pesquisa: [docs/pesquisa/2026-10-30-chatwoot.md](../pesquisa/2026-10-30-chatwoot.md).

## 1. Objetivo

Painel de atendimento **Chatwoot** em `https://atendimento.renpv.com.br`, com os canais WhatsApp
(Cloud API do Meta), Instagram, Facebook Messenger e o widget de chat do site `renpv.com.br`.
Gerenciado pelo repo, como o resto da VPS: script de provisionamento, testes, CI, deploy e backup.

**Muda o modelo de rede do Jarvis:** até aqui nada além de SSH e WireGuard ficava público.
Agora as portas **80 e 443** passam a ser públicas, mas só para o Chatwoot. O dashboard do Hermes
e os apps do Jarvis continuam acessíveis só pela VPN.

## 2. Decisões

| # | Decisão | Por quê |
|---|---|---|
| D1 | Usuário de sistema próprio, `chatwoot`, com **Docker rootless** (como o `hermes`) | O Chatwoot guarda conversas de clientes: nem o Jarvis (`hermes`) nem um container escapado chegam a root ou aos dados um do outro. O Docker de root continua desligado. |
| D2 | `compose.yaml` versionado em `system/chatwoot/`, imagens com **tag e digest** fixos: `chatwoot/chatwoot:v4.18.0`, `pgvector/pgvector:pg16`, `redis:7-alpine` | Reprodutível. Atualização = PR que troca a versão. |
| D3 | O Rails publica só em `127.0.0.1:3000`; Postgres e Redis ficam sem porta publicada (rede interna do compose) | Com Docker, a porta publicada fura o ufw. Só o Caddy chega ao Chatwoot. |
| D4 | Segredos em `/var/lib/chatwoot/.env` (600, do `chatwoot`): `SECRET_KEY_BASE`, `POSTGRES_PASSWORD` e `REDIS_PASSWORD` gerados pelo script; `FB_APP_ID`, `FB_APP_SECRET`, `FB_VERIFY_TOKEN`, `IG_VERIFY_TOKEN` e SMTP preenchidos pelo Renato | O mesmo padrão do `.env` do Hermes: nada secreto no Git nem no chat. |
| D5 | `ENABLE_ACCOUNT_SIGNUP=false`, `FORCE_SSL=true`, `FRONTEND_URL=https://atendimento.renpv.com.br` | Ninguém cria conta sozinho; tudo em HTTPS. |
| D6 | **Um Caddy só, o do sistema.** Sai o `default_bind`/`auto_https off` global; cada site declara o `bind`: os da VPN em `http://… { bind 10.8.0.1 }`, o público `atendimento.renpv.com.br { bind <IP público> }` com certificado Let's Encrypt automático | Com `auto_https off` global, o Caddy não emite certificado. Sem `default_bind`, cada site escuta só onde deve. O `jarvis-expose` passa a gravar `bind 10.8.0.1` nos apps, e o `30-dns-caddy.sh` acrescenta o `bind` nos apps já publicados. |
| D7 | `/installation/*` (criação do primeiro administrador) e `/super_admin*` atrás do **mesmo `basic_auth` do dashboard** | Sem isso, quem abrir o site primeiro cria o super admin. É também uma segunda barreira no console de administração. |
| D8 | ufw libera **80/tcp e 443/tcp** de entrada | Necessário para o HTTPS e para os webhooks do Meta. |
| D9 | O `jarvis-backup` passa a incluir o `pg_dump` do Chatwoot e a pasta `storage` (anexos) | O backup segue enxuto: o dump, não os arquivos brutos do Postgres. |
| D10 | No CI: `tls internal` (sem Let's Encrypt) e sem baixar nem subir as imagens do Chatwoot. O CI valida o compose, o Caddy, o firewall, o usuário e o Docker rootless | Tentativas de emissão a partir do runner gastariam o limite de falhas do Let's Encrypt **do domínio real**, e as imagens somam mais de 1 GB. |

## 3. Peças

- `provision/vars.sh`: `CHATWOOT_USER=chatwoot`, `CHATWOOT_DIR=/var/lib/chatwoot`, `CHATWOOT_DOMAIN=atendimento.renpv.com.br`, `CHATWOOT_PORT=3000`, `PUBLIC_IP` (vazio = descobre pela rota padrão).
- `provision/70-chatwoot.sh`: usuário, subuid/subgid (faixa própria), linger, Docker rootless do `chatwoot`, `.env` (gera o que faltar sem sobrescrever), compose, `db:chatwoot_prepare`, `up -d`, verificação (`curl` em `127.0.0.1:3000`).
- `system/chatwoot/compose.yaml`; `system/caddy/Caddyfile.tpl` (binds por site + bloco público); `bin/jarvis-expose` (bind nos apps); `30-dns-caddy.sh` (ufw 80/443 e migração dos apps); `bin/jarvis-backup` (dump).
- `jarvis status` mostra o Chatwoot.
- `tests/`: bats para o compose (portas só em 127.0.0.1, imagens fixadas), o Caddyfile (`caddy validate`, binds, `basic_auth` no onboarding), o `jarvis-expose` com bind e o backup. A auditoria do CI passa a aceitar 80/443 **só** no IP público e só se forem do Caddy.
- `docs/aprendizado/90-chatwoot.md`: o guia, incluindo os canais do Meta passo a passo.

## 4. Limpeza da tentativa manual (na VPS, uma vez)

- Parar e remover os containers `chatwoot-*` e `caddy-global` do Docker de root e desligar o Docker de root de novo.
- Apagar `~/chatwoot` e `~/caddy`. Não há dados reais, e o banco nunca subiu.
- Tirar o `renpv` do grupo `docker`: esse grupo dá root **sem senha**, e o `renpv` já tem sudo com senha.

## 5. Critérios de aceite

1. `https://atendimento.renpv.com.br` abre com certificado válido. `http://` redireciona para `https://`.
2. `/installation/onboarding` pede usuário e senha (`basic_auth`). Com eles, o Renato cria o administrador.
3. `ss -tulpn` mostra 80/443 **só** no IP público e só do Caddy. `:3000` fica só em `127.0.0.1`.
4. `hermes.jarvis.lan` e `exemplo.jarvis.lan` continuam só pela VPN. Pelo IP público, nada responde para esses nomes.
5. Uma conversa de teste pelo widget aparece no painel.
6. O backup diário contém o dump do Chatwoot, e uma restauração de teste num banco descartável funciona.
7. Os canais do Meta (WhatsApp, Instagram, Messenger) ficam como etapa guiada do Renato, depois que o app do Meta for criado.

## 6. Fora de escopo

SMTP próprio (fica opcional no `.env`), armazenamento S3, alta disponibilidade, o site `renpv.com.br`.
