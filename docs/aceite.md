# Aceite do plano base

Critérios da spec ([2026-10-17-jarvis-base-design.md](specs/2026-10-17-jarvis-base-design.md),
seção 10), verificados na VPS `179.197.74.162` (Ubuntu 24.04, Hermes v0.22.4).

| # | Critério | | Data | Como foi verificado | Observação |
|---|---|---|---|---|---|
| 1 | Pelo Telegram, o Jarvis responde ao dono; outra conta é ignorada | ⏳ | 2026-10-22 | conversa com o bot a partir da conta do Renato | falta mandar uma mensagem **de outra conta** |
| 2 | Com a VPN, `hermes.jarvis.lan` abre o dashboard após o `basic_auth`; sem ela, nada responde | ✅ | 2026-10-22 | navegador pela VPN no minipc; o Caddy escuta só em `10.8.0.1` (`auditoria.bats`: 401 sem senha, pela VPN) | a aba Chat exigiu a correção da Origin no Caddy (#25) |
| 3 | `ss -tulpn` mostra só o SSH e o WireGuard na interface pública | ✅ | 2026-10-22 | `ss -tulpn` na VPS; `auditoria.bats` a cada lançamento | |
| 4 | Comando perigoso pede aprovação e, sem resposta, é negado; comando da `deny` é bloqueado mesmo aprovado | ✅ | 2026-10-23 | `rm -rf` de teste: botões no Telegram, negado após 300 s; `curl … \| sh` bloqueado | a regra `rm -rf /*` saiu da `deny` (casava qualquer caminho absoluto) (#23) |
| 5 | O `hermes` não usa `sudo` além do expose, não lê `/opt/jarvis`, não faz push no `jarvis` | ✅ | 2026-10-22 | verificações do `50-docker-rootless.sh` e da `auditoria.bats`; token do Jarvis recebe 404 em `renpv/jarvis` | |
| 6 | O Jarvis cria um evento no Google Calendar, que aparece no Android | ✅ | 2026-10-23 | "Teste do Jarvis", 24/10 15:00, conferido na API e no celular | OAuth só com o escopo de Calendar (guia 70) |
| 7 | O Jarvis publica um app de exemplo em `http://exemplo.jarvis.lan` | ✅ | 2026-10-23 | app `exemplo` em `127.0.0.1:8100`, aberto pela VPN | no Windows, cada app precisa de uma linha no `hosts` (guia 30) |
| 8 | O Jarvis abre um PR em um repositório de teste | ✅ | 2026-10-23 | PR #1 em `renpv/jarvis-teste`, commit do autor "Jarvis" | título em inglês → SOUL pede português (#31) |
| 9 | O resumo matinal chega no Telegram no horário | ✅ | 2026-10-23 | `jarvis hermes cron run <id>` entregou no Telegram; job às 07:00 | |
| 10 | Um backup é restaurado com sucesso em um diretório de teste | ✅ | 2026-10-23 | restauração do backup das 03:00, `integrity_check` ok; `backup pull` no WSL | backup enxuto: 1,5 MB (#33) |
| 11 | `jarvis diff` mostra uma mudança do dashboard e `jarvis import` a traz para o repo | ✅ | 2026-10-23 | `onboarding.seen` gravado pelo Hermes trazido ao repo (#27); skill editada pelo Jarvis (#32) | o import passou a fazer mescla de três vias (#28) |

## Pendências

1. **Critério 1b:** de outra conta do Telegram, mande uma mensagem ao bot. Esperado: nenhuma resposta.
2. **Skill de tarefas** (não é critério, mas faz parte da Tarefa 17), agora no Google Tasks: "anota a tarefa:
   revisar o backup, para amanhã" e depois "quais minhas tarefas?". Esperado: a tarefa no app Google Tasks e no resumo do dia seguinte.
3. **Opcional:** reiniciar a VPS e conferir que serviços, VPN e o app `exemplo` voltam sozinhos.
4. **Opcional:** uma cópia do backup fora da VPS e de casa (regra 3-2-1, guia 60).
