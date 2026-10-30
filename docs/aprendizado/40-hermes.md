# 40 — O Hermes na VPS

Tarefa 14 do plano base. Script: `provision/40-hermes.sh`. Versão instalada: Hermes Agent v0.22.4.

## Onde ficou cada coisa

O Hermes roda como o usuário de sistema `hermes`, com a home em `/var/lib/hermes` (modo 750):

| Caminho | O quê | Vai para |
|---|---|---|
| `~/.local/bin/hermes` | o comando `hermes` | — (o instalador refaz) |
| `~/.hermes/config.yaml` | configuração | **repo** (`hermes/config.yaml`) |
| `~/.hermes/SOUL.md` | personalidade e regras do Jarvis | **repo** (`hermes/SOUL.md`) |
| `~/.hermes/skills/jarvis/` | as nossas skills | **repo** (`hermes/skills/jarvis/`) |
| `~/.hermes/.env` (600) | chaves: OpenAI, Telegram, GitHub | só na VPS |
| `~/.hermes/memories/`, `sessions/`, `state.db`, `cron/` | memória, conversas, rotinas | backup |
| `~/.hermes/google_token.json` (600) | token do Google Calendar | backup |
| `~/.hermes/hermes-agent/`, `installs/`, `tools/`, `cache/` | código, ambientes Python, node, chromium… | — (o instalador refaz) |
| `~/workspace/`, `~/apps/`, `~/notas/` | pasta de trabalho, apps publicados, tarefas | backup |

O instalador oficial roda **como hermes** (`curl … install.sh | bash -s -- --non-interactive`).
Na VPS real ele falhou na primeira vez: o Node que ele baixa precisa da `libatomic1`, que a
imagem mínima do Ubuntu não traz. O `40-hermes.sh` agora instala esse pacote antes.

## Os serviços

| Serviço | Comando | Para quê |
|---|---|---|
| `hermes-gateway` | `hermes gateway run` | Telegram, cron, pedidos de aprovação |
| `hermes-dashboard` | `hermes dashboard --host 127.0.0.1 --port 9119` | painel web (atrás do Caddy, só pela VPN) |

Os dois rodam como `hermes`, com `XDG_RUNTIME_DIR` e `DOCKER_HOST` apontando para o Docker rootless
(guia 50). O `loginctl enable-linger` mantém a sessão do `hermes` viva no boot.

```bash
jarvis status                                  # serviços, versão, diff
journalctl -u hermes-gateway -n 50 --no-pager  # log do serviço
sudo ls /var/lib/hermes/.hermes/logs/          # logs do próprio Hermes (agent, gateway, errors)
```

## O `config.yaml`

O arquivo padrão tem mais de 2 000 linhas, quase todas comentadas pelo próprio Hermes. O fluxo foi:
`jarvis import` trouxe o padrão como linha de base, o `hermes model` escolheu o modelo, e os
blocos do Jarvis foram acrescentados no repo. O que mudamos:

| Bloco | Valor | Por quê |
|---|---|---|
| `model` | `gpt-6.1-sol`, provedor `openai-api`, `api_mode: codex_responses` | o agente principal (escolhido com `hermes model`, que é interativo; era `gpt-5.5` até 30/10) |
| `auxiliary.compression`, `auxiliary.title_generation` | `gpt-5.4-mini` | tarefas internas (resumir histórico, dar título) com um modelo barato |
| `timezone` | `America/Fortaleza` | datas, cron e agenda no fuso certo |
| `approvals.mode` | `manual` | todo comando perigoso pede aprovação com botões no Telegram |
| `approvals.timeout` | `300` | sem resposta em 5 minutos, o comando é **negado** |
| `approvals.cron_mode` | `deny` | rotina agendada não tem quem aprove: comando perigoso é negado |
| `approvals.deny` | `git push --force*`, `git push -f*`, `*curl*\|*sh*`, `*wget*\|*sh*`, `dd if=* of=/dev/*`, `*sudoers*` | bloqueados **mesmo com aprovação** |
| `security.redact_secrets` | `true` | chaves somem das respostas e dos logs |
| `checkpoints.enabled` | `true` | o Hermes guarda o estado dos arquivos antes de mexer neles |
| `display.language` | `pt` | botões, avisos e pedidos de aprovação em português |
| `stt.language` | `pt` | transcrição dos áudios do Telegram em português |

### Lição: o glob da deny list casa mais do que parece

A primeira lista tinha `'rm -rf /*'`. O `*` do glob casa **qualquer coisa**, então ela bloqueava
todo `rm -rf` com caminho absoluto, inclusive na pasta de trabalho do próprio Jarvis. Conferimos
no código do Hermes (`tools/approval.py`) que ele já tem uma lista fixa (*hardline*) que barra
`rm -rf /` e variantes. A regra saiu, e o motivo ficou comentado no `config.yaml`.

### Estado que o Hermes grava no `config.yaml`

O Hermes também usa o `config.yaml` para guardar estado, como `onboarding.seen` depois de oferecer
o perfil. Isso aparece no `jarvis diff` como mudança do Hermes. Traga com `jarvis import`
(que faz mescla de três vias: guia 80, seção 6) e leve ao repo.

## O dia a dia

```bash
jarvis diff               # repo × Hermes vivo
jarvis apply              # repo → Hermes (recusa se o Hermes mudou algo; veja o diff)
jarvis import             # Hermes → repo (mescla de três vias)
jarvis hermes config check
jarvis hermes <comando>   # qualquer comando do hermes, como o usuário hermes
```

O próprio Jarvis também edita as skills dele. Depois de publicar o primeiro app, ele acrescentou
duas lições à skill `publicar-app`. Isso apareceu no `jarvis diff` e foi para o repo no #32.

## Resultados dos testes (critérios 1, 2 e 4)

- **Telegram:** responde em português ao Renato. Uma mensagem de outra conta deve ser ignorada:
  esse teste está pendente (veja `docs/aceite.md`).
- **Dashboard:** `http://hermes.jarvis.lan` pede senha e abre. A aba Chat só conectou depois
  da correção da Origin no Caddy (guia 30).
- **Aprovação:** `rm -rf` numa pasta de teste trouxe os botões no Telegram. Sem resposta, foi
  negado em 300 s (`BLOCKED: Command timed out without user response`), e a pasta continuou lá.
  - Depois de uma recusa, o Jarvis às vezes se recusa a tentar de novo, porque lembra da conversa.
    `/new` no Telegram começa uma sessão limpa.
- **Deny list:** `curl … | sh` foi bloqueado mesmo com aprovação.
