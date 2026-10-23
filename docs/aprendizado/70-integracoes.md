# 70 — Integrações: GitHub, Google Calendar, cron e tarefas

Tarefa 17 do plano base.

## GitHub

O Jarvis usa o `GITHUB_TOKEN` do `.env`, que é um token **fine-grained** com acesso:
- **só** ao repositório `renpv/jarvis-teste`;
- permissões *Contents*, *Pull requests* e *Issues* em leitura e escrita;
- validade de 90 dias (veja `docs/operacao.md`, seção 6).

**Por que o repo `jarvis` fica fora:** é ele que define a configuração do próprio Jarvis e o que a
VPS roda. Se o Jarvis pudesse dar push nele, um prompt malicioso (num e-mail, numa página, numa
issue) poderia fazê-lo mudar as próprias regras, e a mudança chegaria à VPS no próximo deploy.
A conferência é simples: com o token do Jarvis, `renpv/jarvis` responde **404**.

O primeiro token era clássico (`ghp_…`, escopo `repo`), e esse tipo alcança **todos** os repos da
conta. Foi trocado por um fine-grained antes de qualquer teste.

**Resultado (critério 8, 23/10):** o Jarvis abriu o PR #1 em `renpv/jarvis-teste`. Ele pediu
confirmação antes do push e do PR.
- O commit tem a autoria `Jarvis <jarvis@srv2065375>` (a identidade git do `40-hermes.sh`).
- O PR aparece como `renpv`, porque o GitHub atribui o PR ao dono do token.
- O título e o commit saíram em inglês. Por isso o `SOUL.md` passou a pedir português também
  em commits, PRs e issues (#31).

## Google Calendar

Usamos a skill `google-workspace`, que vem com o Hermes, liberando **só** o escopo de Calendar.

### 1. Google Cloud

1. **Projeto:** a conta tinha batido no limite de projetos do período de teste gratuito. Reaproveitamos
   um projeto pessoal que já existia: um projeto pode ter vários clientes OAuth.
2. **API:** só a *Google Calendar API* ativada.
3. **Tela de consentimento:** tipo *External*, nome `Jarvis`.
   - Para publicar, o Google exige página inicial e política de privacidade. Usamos
     `https://github.com/renpv` e um gist público com uma política curta.
4. **Publicar** (*Audience → Publish app*, "In production"). **Isso é importante:** com o app em
   *Testing*, o Google invalida o token **a cada 7 dias**. Sem verificação, o Google mostra o aviso
   "app não verificado" e limita o app a 100 usuários. Nenhuma das duas coisas atrapalha o uso pessoal.
5. **Cliente OAuth:** tipo *Desktop app*, com a opção "Use this client for an AI-powered agent"
   marcada. A opção só declara o uso por um agente: não dá escopo a mais, e alguns endpoints MCP
   do Google exigem essa marcação.

### 2. Autorização (na VPS, sem passar pelo chat do Jarvis)

Rodamos o script da skill direto, como `hermes`. Assim o código de autorização não passa pelo
modelo nem fica no histórico de conversas:

```bash
GPY=$(sudo -u hermes bash -c 'ls -d /var/lib/hermes/.hermes/installs/*/environments/*/venv/bin/python | head -1')
GS=/var/lib/hermes/.hermes/skills/productivity/google-workspace/scripts/setup.py
sudo -u hermes -H "$GPY" "$GS" --client-secret /caminho/do/client_secret.json
```

**Armadilha:** a documentação da skill manda usar `--auth-url --services calendar`, mas essa opção
**não existe** no `setup.py` (nem na v0.22.4, nem no `main` de out/2026). Sem ela, o script pede os
8 escopos (Gmail, Drive, Contatos, Docs, Sheets e Calendar). Na primeira tentativa, a tela do Google
não ofereceu caixas para desmarcar, e a URL de retorno veio com todos os escopos. O código foi
descartado sem uso. O que funcionou foi carregar o script como módulo e trocar a lista antes de gerar a URL:

```bash
sudo -u hermes -H "$GPY" -c 'import sys; sys.path.insert(0, sys.argv[1]); import setup as s; s.SCOPES = ["https://www.googleapis.com/auth/calendar"]; s.get_auth_url()' "$(dirname "$GS")"
```

Depois de autorizar, o navegador cai em `http://localhost:1/?...&code=...&scope=...` e mostra
`ERR_UNSAFE_PORT`. Isso é esperado. Confira se o `scope=` traz **só** `.../auth/calendar` e troque o código:

```bash
sudo -u hermes -H "$GPY" "$GS" --auth-code 'URL_INTEIRA' && sudo -u hermes -H "$GPY" "$GS" --check
```

O esperado é `AUTHENTICATED (partial)`, listando os 7 escopos recusados de propósito. O
`google_api.py` usa os escopos gravados no token, então a agenda funciona normalmente.

O código de autorização vale uma vez só, expira em minutos e usa PKCE: sem o
`google_oauth_pending.json` da VPS, ele não serve para nada.

### 3. Onde fica e quanto dura

| Arquivo | Conteúdo |
|---|---|
| `~/.hermes/google_client_secret.json` (600) | o cliente OAuth |
| `~/.hermes/google_token.json` (600) | o token, que se renova sozinho |

O script grava os dois com modo 664. Nós apertamos para 600, igual ao `.env`. O token vale até ser
revogado, em https://myaccount.google.com/permissions. Se o app voltar para *Testing*, ele passa a
expirar em 7 dias. Os dois arquivos entram no backup.

**Resultado (critério 6, 23/10):** "marca um teste do Jarvis amanhã às 15h" criou o evento
"Teste do Jarvis" em 24/10, 15:00 (−03). O evento foi conferido na API do Google, e o Renato
conferiu no celular. A consulta da semana também funcionou.

## Cron

As rotinas ficam em `~/.hermes/cron/`, que é estado (entra no backup e não vai para o repo).
Elas foram criadas com:

```bash
jarvis hermes cron create "0 7 * * *" "Resumo matinal para Renato, em português e em no máximo 10 linhas: 1) eventos de hoje no Google Calendar (fuso America/Fortaleza); se a agenda ainda não estiver configurada, diga isso em uma linha; 2) tarefas pendentes com data até hoje no Google Tasks (skill tarefas: scripts/tarefas listar --ate <hoje>); 3) uma linha de alerta só se 'systemctl --failed --no-legend' mostrar algo." --name "Resumo matinal" --deliver telegram
jarvis hermes cron create "0 10 * * 0" "Lembre Renato, em português e em uma linha, de rodar './bin/jarvis backup pull' no computador (com a VPN ligada) para copiar os backups da VPS." --name "Lembrete de backup" --deliver telegram
```

| Ação | Comando |
|---|---|
| listar | `jarvis hermes cron list` |
| disparar agora | `jarvis hermes cron run <id>` |
| editar | `jarvis hermes cron edit <id>` |
| pausar / retomar | `jarvis hermes cron pause <id>` / `resume <id>` |
| remover | `jarvis hermes cron remove <id>` |

A aba **Cron** do dashboard faz o mesmo. Com `approvals.cron_mode: deny`, uma rotina não consegue
rodar comando perigoso, porque não há quem aprove.

**Resultado (critério 9, 23/10):** o `cron run` do resumo entregou a mensagem no Telegram em
segundos. O resumo foi disparado antes de o Calendar estar configurado; a linha de agenda só passa
a vir preenchida a partir dali.

## Tarefas (Google Tasks)

Até 23/10 as tarefas ficavam num arquivo na VPS (`~/notas/tarefas.md`). Elas passaram para o
**Google Tasks**, que tem caixinha de concluído, aceita tarefa sem data e aparece no app Google
Tasks do Android e, as que têm data, no Google Agenda.

A skill `google-workspace` do Hermes não cobre o Google Tasks. Por isso a nossa skill `tarefas` tem
um script próprio, `scripts/google_tasks.py`, que usa as bibliotecas do Google do Hermes e o mesmo
`google_token.json`. Ele é chamado pelo `scripts/tarefas`, que procura o Python do Hermes:

```bash
T=~/.hermes/skills/jarvis/tarefas/scripts/tarefas
$T listar [--ate AAAA-MM-DD]
$T criar "título" [--data AAAA-MM-DD] [--notas "#etiqueta"]
$T concluir <id> | adiar <id> AAAA-MM-DD | apagar <id>
```

Para isso, o token precisa de dois escopos: `calendar` e `tasks`. A *Google Tasks API* foi ativada
no mesmo projeto, e a autorização foi refeita com o mesmo truque da seção anterior, trocando a lista por:

```python
s.SCOPES = ["https://www.googleapis.com/auth/calendar", "https://www.googleapis.com/auth/tasks"]
```

O script é testado sem rede, com um Google Tasks falso (`tests/google_tasks_test.py`).
