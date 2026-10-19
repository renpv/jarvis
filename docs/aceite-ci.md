# Aceite — CI e fluxo Git

Critérios da [spec](specs/2026-10-18-ci-e-fluxo-git-design.md), seção 11. Verificados em 2026-10-19.

| # | Critério | Resultado | Como foi verificado |
|---|---|---|---|
| 1 | PR para `main` com erro de shellcheck fica vermelho em `lint` | ✅ | PR renpv/jarvis#9 (`provision/zz-aceite.sh` com `echo $1`): `lint` reprovou. Fechado sem merge. |
| 2 | PR com token falso fica vermelho em `secrets` | ✅ | PR renpv/jarvis#10 (token aleatório no formato `ghp_…`): `secrets` (gitleaks) reprovou, e `unit` também (varredura de `tests/repo.bats`). Fechado sem merge; branch apagado. |
| 3 | Workflow com ação por tag fica vermelho em `workflow-security` | ✅ | PR renpv/jarvis#11 (`actions/checkout@v4`): `workflow-security` (zizmor) reprovou, e `unit` também (`tests/workflows.bats`). Fechado sem merge. |
| 4 | PR para `prod` vindo de outro branch fica vermelho em `origem` | ✅ | PR renpv/jarvis#12 (`feat/aceite-origem` → `prod`): `origem` reprovou e a `integracao` foi pulada. Fechado sem merge. |
| 5 | `integracao` roda `00`→`60` e toda a auditoria passa | ✅ | Run 39204016680 (push no `prod`) e o PR de lançamento renpv/jarvis#8: dois provisionamentos (idempotência), 12/12 testes de auditoria (incluindo o ataque de link simbólico com o `hermes` real) e Lynis 64. |
| 6 | `jarvis deploy` na VPS avança com checks verdes e recusa com vermelho/ausente | ⏳ | Coberto por 16 testes de unidade (`tests/deploy.bats`). A verificação real fica para a Fase B do plano base, quando a VPS existir. |
| 7 | Com `make hooks`, commit com token falso é bloqueado localmente | ✅ | Branch local descartável: o pre-commit (gitleaks) encontrou 1 vazamento e o commit não aconteceu. |
| 8 | Dependabot abre PR de atualização e ele passa no portão 1 | ⏳ | Aguardando o primeiro PR do Dependabot (agenda semanal, cooldown de 14 dias). |
| 9 | Push direto para `main` é recusado localmente; `feat/*` quebrado é recusado; tudo verde passa | ✅ | Contra um repositório local descartável: push para `main` e para `prod` recusados com "use um PR" (0 refs enviados). O caminho verde foi exercitado em todos os pushes de `feat/*` e `fix/*` desta implantação. O vermelho está coberto por `tests/hooks.bats`. |
| 10 | Com `TIMEZONE=America/Fortalesa` e `WG_PORT=99999`, o preflight lista os dois erros sem alterar nada | ✅ | `preflight` mostrou "2 problema(s) — nada foi alterado", listou `TIMEZONE` e `WG_PORT` e saiu com 1. A sentinela de `tests/preflight.bats` comprova que nada roda depois. |
| 11 | `jarvis check` numa VPS saudável mostra tudo ✅; sem o token, ❌ e sai com 1 | ⏳ | Coberto por `tests/check.bats`. A verificação real fica para a Fase B do plano base. |

## O que a primeira execução real da integração encontrou

Foram 5 rodadas até o primeiro verde. Cada falha era um problema real, e a correção ficou no código:

| Rodada | Problema | Correção |
|---|---|---|
| 1 | `XDG_CONFIG_HOME` do runner vazava para os comandos do `hermes` | `as_hermes` com `env -i` (renpv/jarvis#3) — também protege a VPS |
| 2 | Docker rootless não subia: o runner não instala *Recommends* e faltou o `slirp4netns` | dependências explícitas no `50` (renpv/jarvis#4) |
| 3 | Docker rootless usava `/run/user/1001` (o diretório do `runner`) | diagnóstico completo no `50` (renpv/jarvis#5) |
| 4 | Causa: o `/etc/environment` do runner é injetado pelo PAM em toda sessão | o CI deixa o arquivo igual ao de uma VPS (renpv/jarvis#6) |
| 5 | ✅ verde | — |

## Pendências

- **6 e 11:** verificar na VPS, na Fase B do plano base. Na Tarefa 12 de lá, depois de criar o token, rode `jarvis check`; na primeira mudança real, `jarvis deploy`.
- **8:** registrar aqui o primeiro PR do Dependabot quando ele aparecer.
