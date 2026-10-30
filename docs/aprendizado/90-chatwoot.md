# 90 — Chatwoot (atendimento)

Design: [2026-10-30-chatwoot-design.md](../specs/2026-10-30-chatwoot-design.md).
Pesquisa com as fontes: [2026-10-30-chatwoot.md](../pesquisa/2026-10-30-chatwoot.md).
Script: `provision/70-chatwoot.sh`.

## Como ficou

```
internet ──► :80/:443 no IP público ──► Caddy ──► 127.0.0.1:3000 (Rails)
                                                   │
                       Docker rootless do usuário chatwoot: rails, sidekiq, postgres (pgvector), redis
```

- É o **único serviço público** da VPS. O dashboard do Hermes e os apps continuam só na VPN.
  Cada site do Caddy declara o próprio `bind` (guia 30).
- O usuário `chatwoot` tem um Docker rootless próprio, separado do `hermes`. Um não lê os arquivos
  do outro, e os containers dos dois usam faixas de UID diferentes.
- As imagens têm versão e digest fixos em `system/chatwoot/compose.yaml`.
- `/installation/*`, onde se cria o primeiro administrador, e `/super_admin*` pedem um **usuário e
  senha próprios** (`basic_auth` do Caddy) antes do login do próprio Chatwoot. A senha é aleatória,
  foi gerada pelo `30-dns-caddy.sh` e fica em `/etc/caddy/chatwoot-portao.txt` (root, 600). Não é a
  senha do dashboard, que assim não fica exposta na internet.
- Uma regra **nftables** (`jarvis-chatwoot-porta.service`) fecha `127.0.0.1:3000` para todo usuário
  que não seja `caddy`, `chatwoot` ou root. Sem ela, o `hermes` (ou qualquer usuário local) falaria
  direto com o Rails e pularia o portão.

| Caminho na VPS | O quê |
|---|---|
| `/var/lib/chatwoot/compose.yaml` | cópia do repo (o `70` regrava) |
| `/var/lib/chatwoot/.env` (600) | segredos gerados uma vez e campos do Meta e do SMTP para preencher |
| `/var/lib/chatwoot/storage/` | anexos (entra no backup) |
| `/var/lib/chatwoot/postgres/`, `redis/` | dados brutos (não entram; o backup leva um `pg_dump`) |

## Primeiro acesso

1. Na VPS, `sudo cat /etc/caddy/chatwoot-portao.txt` mostra o usuário e a senha do portão.
2. Abra `https://atendimento.renpv.com.br/installation/onboarding`. O Caddy pede esse usuário e essa senha.
3. Crie a conta de administrador (nome, e-mail, senha forte). O cadastro público fica desligado
   (`ENABLE_ACCOUNT_SIGNUP=false`), e novos agentes entram por convite.

## Comandos

```bash
sudo -u chatwoot -H bash -c 'cd ~ && export XDG_RUNTIME_DIR=/run/user/$(id -u) DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock && docker compose ps'
sudo -u chatwoot -H bash -c 'cd ~ && export XDG_RUNTIME_DIR=/run/user/$(id -u) DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock && docker compose logs --tail 50 rails'
sudo -u chatwoot nano /var/lib/chatwoot/.env      # depois: sudo provision/70-chatwoot.sh
```

**Atualizar a versão:**
1. Num `feat/*`, troque a tag e o digest em `system/chatwoot/compose.yaml`. Use uma imagem com pelo
   menos 14 dias e leia as notas da versão.
2. Depois do PR, do lançamento e do deploy, rode `sudo provision/70-chatwoot.sh`. Ele roda o
   `db:chatwoot_prepare` (migrações) antes de subir.

## Canais

Todos usam a URL pública em HTTPS. As URLs de webhook seguem o padrão do Chatwoot:

| Canal | Webhook | Variáveis no `.env` |
|---|---|---|
| WhatsApp (Cloud API do Meta) | `https://atendimento.renpv.com.br/webhooks/whatsapp/<número>` | nenhuma: o token de verificação é por caixa de entrada, mostrado no Chatwoot |
| Facebook Messenger | `https://atendimento.renpv.com.br/bot` | `FB_APP_ID`, `FB_APP_SECRET`, `FB_VERIFY_TOKEN` (gerado) |
| Instagram | `https://atendimento.renpv.com.br/webhooks/instagram` | `FB_APP_ID`, `FB_APP_SECRET`, `IG_VERIFY_TOKEN` (gerado) |
| Chat do site | — | nenhuma: o Chatwoot gera o script do widget para colar no site |

O roteiro guiado do app do Meta fica para a etapa seguinte. Os nomes das telas do Meta mudam com
frequência, então vamos segui-lo junto, consultando a documentação do dia.

**SMTP:** sem SMTP não há convite de agentes nem recuperação de senha por e-mail. Preencha os
campos `SMTP_*` e `MAILER_SENDER_EMAIL` no `.env` quando tiver uma conta de envio.

## Backup

O `jarvis-backup` diário leva `chatwoot/chatwoot.dump` (`pg_dump -Fc`, feito com o Chatwoot no ar)
e `chatwoot/storage/`. Se o dump falhar, o backup inteiro falha: o timer fica vermelho e o resumo
matinal acusa. Restaurar o banco num container de teste:

```bash
tar -I zstd -xOf BACKUP.tar.zst chatwoot/chatwoot.dump > /tmp/cw.dump
docker run --rm -d --name cw-teste -e POSTGRES_PASSWORD=x pgvector/pgvector:0.8.7-pg16
docker cp /tmp/cw.dump cw-teste:/tmp/ && docker exec cw-teste sh -c 'sleep 5; createdb -U postgres chatwoot && pg_restore -U postgres -d chatwoot --no-owner /tmp/cw.dump && psql -U postgres -d chatwoot -c "select count(*) from users"'
docker rm -f cw-teste
```

## No CI

O `70` roda na `integracao`, mas **não sobe** o Chatwoot: as imagens somam mais de 1 GB, e o
Chatwoot pede ~4 GB de RAM. O CI valida o compose, o usuário, o Docker rootless, o `.env`, o Caddy
e o firewall. O site usa `tls internal` no CI: tentar o Let's Encrypt a partir do runner gastaria o
limite de falhas de validação do domínio real.

## A tentativa manual de 29/10

Antes deste script, uma tentativa à mão ficou na VPS:
- o Docker de root foi religado;
- o Rails estava publicado em `0.0.0.0:3000`, o que **fura o ufw**;
- havia um segundo Caddy em container, nas portas 80/443.

Ela foi desfeita: os containers foram parados, o Docker de root desligado de novo, o `renpv` saiu
do grupo `docker` (que dá root sem senha) e as pastas foram movidas para
`/root/tentativa-manual-chatwoot-20261030`, sem dados reais. Pode apagar essa pasta quando quiser.
