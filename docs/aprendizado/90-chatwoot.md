# 90 — Chatwoot (atendimento)

Design: [2026-10-30-chatwoot-design.md](../specs/2026-10-30-chatwoot-design.md).
Pesquisa com as fontes: [2026-10-30-chatwoot.md](../pesquisa/2026-10-30-chatwoot.md).
Script: `provision/70-chatwoot.sh`.

Este guia cresce com o uso: cada lição nova sobre o Chatwoot ou os canais do Meta entra aqui, na
seção do assunto.

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

Os comandos com `sudo` precisam de root na VPS. Quando um agente faz o trabalho, ele usa o
**sudo temporário**: uma regra que se valida antes de entrar e se apaga sozinha em 2 horas. Rode
dentro da VPS (`ssh jarvis`), não no WSL:

```bash
t=$(mktemp) && echo 'renpv ALL=(ALL) NOPASSWD: ALL' > "$t" && sudo visudo -cf "$t" && sudo install -m 0440 -o root -g root "$t" /etc/sudoers.d/90-claude-temporario && sudo systemd-run --on-active=2h --unit=remover-sudo-claude rm -f /etc/sudoers.d/90-claude-temporario; rm -f "$t"
```

Para conferir: `systemctl list-timers --all | grep remover-sudo`. Se não aparecer nada, o comando
rodou na máquina errada. Ao terminar antes do prazo:
`sudo systemctl stop remover-sudo-claude.timer; sudo rm -f /etc/sudoers.d/90-claude-temporario`.

### Atualizar a versão

A versão em uso está em `system/chatwoot/compose.yaml` e em `https://atendimento.renpv.com.br/api`
(`"version"`).

1. **Escolher a versão:** `gh api repos/chatwoot/chatwoot/releases` lista as datas. Use uma com pelo
   menos 14 dias.
2. **Ler o que muda:**
   - as notas de cada versão no caminho, atrás de "breaking", "migrate" e "retired". Exemplo: a
     v4.19.0 aposentou o Captain V1;
   - o compose oficial nas duas tags (`docker-compose.production.yaml`);
   - o `.env.example` (`gh api repos/chatwoot/chatwoot/compare/vA...vB`).

   Uma variável nova só importa se não for opcional.
3. **PR:** num branch `fix/*` ou `feat/*` (o pre-push recusa outros nomes), troque a tag e o digest.
   Confira o digest com `docker buildx imagetools inspect chatwoot/chatwoot:<tag>`.
4. **Antes de subir:** confira no banco o que as notas pedem (por exemplo,
   `select count(*) from captain_assistants`) e faça um backup na hora:
   `sudo systemctl start jarvis-backup`.
5. **Subir:** lançamento e deploy (skill `lancamento`). Depois, `sudo provision/70-chatwoot.sh`, que
   baixa a imagem, roda o `db:chatwoot_prepare` (migrações) e recria o `rails` e o `sidekiq`.
   O atendimento fica fora do ar por cerca de 1 minuto.
6. **Conferir:**
   - o `/api` mostra a versão nova, com `queue_services` e `data_services` em `ok`. Um
     `data_services: failing` logo depois de subir pode ser só a conexão ainda não aberta: abra
     `/app/login` e repita (ver "Onde olhar quando algo falha");
   - `docker compose ps` mostra as imagens com o digest;
   - os logs não têm `ERROR`;
   - uma mensagem de WhatsApp vai e volta.

Histórico: v4.18.0 na instalação (2026-10-30), v4.19.1 em 2026-11-15.

## Canais

Todos usam a URL pública em HTTPS. As URLs de webhook seguem o padrão do Chatwoot:

| Canal | Estado | Webhook | Chaves |
|---|---|---|---|
| WhatsApp (Cloud API do Meta) | ligado | `https://atendimento.renpv.com.br/webhooks/whatsapp/<número>` | nenhuma no `.env`: o token fica na caixa de entrada, colado na tela do Chatwoot |
| Facebook Messenger | não ligado | `https://atendimento.renpv.com.br/bot` | `FB_APP_ID`, `FB_APP_SECRET`, `FB_VERIFY_TOKEN` (gerado) |
| Instagram | em espera: falta a conta profissional | `https://atendimento.renpv.com.br/webhooks/instagram` | `INSTAGRAM_APP_ID`, `INSTAGRAM_APP_SECRET`, `INSTAGRAM_VERIFY_TOKEN` (ver abaixo) |
| Chat do site | não ligado | — | nenhuma: o Chatwoot gera o script do widget para colar no site |

O app do Meta é um só ("Jarvis") para todos os canais. Cada canal entra nele como um caso de uso.

### Messenger

- As mensagens chegam numa **Página do Facebook**, não num perfil pessoal. É preciso ser
  administrador da Página.
- No app: caso de uso do Messenger, permissões `pages_messaging`, `pages_manage_metadata` e
  `pages_show_list`, e webhook `/bot` com o campo `messages`.
- Enquanto o app estiver em desenvolvimento, só quem tem função no app conversa. Para o público, o
  Meta pede a verificação da empresa e a revisão do app.

### Instagram

Desde a v4.1, o Chatwoot liga o Instagram pelo **login do próprio Instagram**, sem Página do
Facebook (código da v4.18: `Instagram::IntegrationHelper`, `config/installation_config.yml`). O
fluxo antigo, pela Página, usava `FB_APP_ID` e `IG_VERIFY_TOKEN` e foi descontinuado.

1. **Instagram:** a conta precisa ser profissional (Empresa ou Criador de conteúdo), com
   Configurações > Mensagens e respostas > Ferramentas conectadas > "Permitir acesso às mensagens".
2. **App do Meta:**
   - caso de uso "Gerenciar mensagens e conteúdo no Instagram" (API do Instagram com login do Instagram).
     Ele tem ID e chave secreta próprios, diferentes dos do app do Facebook;
   - redirecionamento do login: `https://atendimento.renpv.com.br/instagram/callback`;
   - webhook `/webhooks/instagram`, com o campo `messages`;
   - em Funções, a conta do Instagram como testador (aceite o convite no Instagram). Assim o app
     funciona para a própria conta sem a revisão do Meta.

   O Chatwoot pede as permissões `instagram_business_basic` e `instagram_business_manage_messages`.
3. **Chatwoot:** as três chaves `INSTAGRAM_*` ainda não estão no `70-chatwoot.sh`. A decisão
   pendente é entre o Super Admin (`/super_admin`, atrás do portão do Caddy; fica no banco, que entra
   no backup) e o `.env` por PR. Depois: Configurações > Caixas de entrada > Nova > Instagram.

### WhatsApp

**Como está:** a caixa "Simplifica Negócio WhatsApp" usa o número virtual da BRDID
(+55 85 3179-1619), ligado na Cloud API desde 2026-11-06 e testado nos dois sentidos em 2026-11-15.
A caixa "Test Number WhatsApp", do número de teste dos EUA, ficou sem uso.

**Como se liga um número**, pelo fluxo manual do Chatwoot:
- os dados vêm do painel do Meta: ID do número, ID da conta do WhatsApp Business e o token
  permanente de um usuário do sistema (expiração "Nunca", permissões `whatsapp_business_management`
  e `whatsapp_business_messaging`);
- tudo é colado na tela do Chatwoot, e nada muda no `.env`.

#### O que aprendemos na primeira ligação (2026-10-30, número de teste)

- **Onde fica o webhook no painel novo do Meta:** o WhatsApp não está no menu da esquerda; fica em
  Casos de uso > "Conectar-se com clientes pelo WhatsApp" > Personalizar, e o webhook em
  Configuração de produção > Configurar webhooks. A aba Configuração da caixa no Chatwoot mostra só o
  token de verificação; a URL é a do padrão acima. Assine apenas o campo `messages`.
- **A conta precisa estar inscrita no app.** O Meta verificou o webhook, mas não mandava nenhum
  `POST`: a conta do WhatsApp Business estava inscrita só no app interno do Meta, não no nosso. O
  fluxo manual do Chatwoot não fez a inscrição. Conferir e inscrever, com o token que o Chatwoot
  guarda, sem exibi-lo:

  ```bash
  tok=$(sudo runuser -u chatwoot -- sh -c 'cd /var/lib/chatwoot && XDG_RUNTIME_DIR=/run/user/$(id -u) docker compose exec -T postgres psql -U chatwoot -d chatwoot -Atc "select provider_config->>'"'"'api_key'"'"' from channel_whatsapp limit 1"')
  curl -s -H "Authorization: Bearer $tok" https://graph.facebook.com/v22.0/<ID_DA_CONTA>/subscribed_apps
  curl -s -X POST -H "Authorization: Bearer $tok" https://graph.facebook.com/v22.0/<ID_DA_CONTA>/subscribed_apps
  ```

  Refazer a conferência sempre que trocar de número ou de conta.
- **Nono dígito:** o WhatsApp identifica contas brasileiras sem o 9 (`55DD9XXXXYYYY` vira `55DDXXXXYYYY`), e o Chatwoot
  responde para esse formato. Com o número de teste, cadastre o destinatário também sem o 9, ou o
  Meta recusa com `131030 Recipient phone number not in allowed list`.
- **Número de teste não responde para o Brasil:** depois do nono dígito, o envio parou em `130497
  Business account is restricted from messaging users in this country`. Desde setembro de 2025 o
  Meta restringe mensagens entre países para Brasil e Indonésia em contas novas (o número de teste é
  dos EUA). O recebimento funcionou; o envio fica validado com um número brasileiro.
- **Número virtual no app:** o número da BRDID foi bloqueado pelo WhatsApp Business ao conectar o
  WhatsApp Web. Na Cloud API não há app nem QR code; um número só pode estar em um dos dois.

#### O que aprendemos com o número real (2026-11-15)

- **O `health_status` mostra o bloqueio exato.** Antes de suspeitar do Chatwoot, pergunte ao Meta.
  Ele lista o que trava o número, a conta, a empresa e o app, com o código e a solução:

  ```bash
  curl -s -H "Authorization: Bearer $tok" "https://graph.facebook.com/v22.0/<ID_DO_NUMERO>?fields=health_status,status,code_verification_status,platform_type,account_mode,messaging_limit_tier"
  ```

  O que apareceu aqui, e o que cada um bloqueia:

  | Código | O que é | O que bloqueia |
  |---|---|---|
  | `141006` | erro no método de pagamento da conta | só as mensagens de modelo, que a empresa usa para iniciar uma conversa. Responder dentro de 24h funciona. |
  | `141010` | empresa não verificada | nada; o limite fica em 250 conversas por dia |
  | aviso do nome exibido | nome em aprovação | nada; segura o aumento do limite |
  | `138024`/`138025` | chamadas por SIP | nada; só vale para ligações |

- **Teste de registro sem mudar nada:** uma mensagem de texto pela API para um número seu separa os
  casos. O Claude Code barra esse envio sem o ok do Renato, porque é uma comunicação para fora.
  - `133010 Account not registered`: falta o passo `/register` com o PIN;
  - a API aceita e o status chega ao webhook com `131047 Re-engagement message`: o número está
    registrado e o webhook funciona. O 131047 só diz que passou da janela de 24h;
  - a mensagem chega: tudo certo.
- **"Ocorreu um erro" no celular de quem escreve** não é problema do servidor quando outro celular
  consegue. O suspeito é a conversa antiga guardada no aparelho, do tempo em que o número estava no
  app WhatsApp Business. Apague a conversa e escreva de novo por `https://wa.me/<número>`.
- **Número fixo virtual não tem o nono dígito.** Salve como `+55 DD XXXX-YYYY`; com o 9 na frente,
  é outro número.

#### Onde olhar quando algo falha

1. **Meta:** `health_status` (acima). Ele aponta o bloqueio.
2. **Chegou ou não:** `docker compose logs --since 30m rails | grep 'POST "/webhooks/whatsapp'`.
   - nenhum `POST`: confira o `subscribed_apps` e a URL do webhook no app;
   - só `GET`: o Meta verificou o endereço, mas ninguém escreveu ainda.
3. **O que o Meta disse sobre um envio:** o status volta num `POST` do webhook. Nos logs, procure
   `statuses`, `status` e `errors` no corpo.
4. **Erro de envio no banco** (no `psql` do Chatwoot):
   `select id, status, content_attributes from messages where message_type=1 order by id desc limit 5`.
   - O `status` vale 0 para enviada, 1 para entregue, 2 para lida e 3 para falhou;
   - o `external_error` traz o código do Meta.
5. **`/api` com `data_services: failing`** (visto em 2026-11-20): o Chatwoot calcula com
   `ActiveRecord::Base.connection.active?`, que dá falso enquanto o processo não abriu a conexão
   (o Rails conecta só na primeira consulta). Os containers estavam de pé, o Postgres sem erro e o
   login consultando o banco. Depois de abrir `/app/login`, o `/api` voltou a `ok`. Antes de
   mexer, faça essa prova. Se continuar `failing`, leia `docker compose logs postgres`.

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
