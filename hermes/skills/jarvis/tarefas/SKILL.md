---
name: tarefas
description: Gerencia as tarefas de Renato no Google Tasks (lista "Minhas tarefas"), pelo script scripts/tarefas
version: 2.0.0
author: Renato e Jarvis
platforms: [linux]
metadata:
  hermes:
    tags: [produtividade, tarefas, jarvis, google]
---

# Tarefas

## Quando usar
Quando Renato pedir para anotar, listar, concluir, adiar ou apagar tarefas ("me lembra de...",
"o que tenho pendente?", "marquei X como feito").
Lembrete com hora marcada ("me avisa amanhã às 15h") é cron, não tarefa — use o cron do Hermes,
com entrega no Telegram, e também anote a tarefa se fizer sentido.
Compromisso com horário (reunião, consulta) é evento do Google Calendar, não tarefa.

## Onde ficam
No Google Tasks de Renato, lista padrão ("Minhas tarefas"). Ele vê no app Google Tasks do Android
e, as que têm data, no Google Agenda. Use sempre o script abaixo; não use outra ferramenta para isso.

```bash
T=~/.hermes/skills/jarvis/tarefas/scripts/tarefas
$T listar                                   # pendentes, por data (sem data no fim)
$T listar --ate 2026-10-23                  # vencidas e do dia
$T criar "Pagar a conta de luz" --data 2026-10-24 --notas "#casa"
$T criar "Ler o artigo sobre WireGuard"     # sem data
$T concluir <id>
$T adiar <id> 2026-10-30
$T apagar <id>
```

A saída é JSON: `{"id", "titulo", "data", "notas"}`. O `id` vem do `listar`.

## Regras
- Datas relativas ("sexta", "amanhã") viram AAAA-MM-DD no fuso America/Fortaleza antes de chamar o script.
- Etiquetas (#casa, #estudo) vão em `--notas`.
- Para concluir, adiar ou apagar: rode `listar`, ache a tarefa pelo título e use o `id`.
  Se houver mais de uma parecida, pergunte qual.
- Apagar é definitivo: confirme com Renato antes. Concluir não precisa de confirmação.
- Confirme para Renato em uma linha o que mudou (título e data).

## Se der erro
- "não tem o escopo do Google Tasks": o token precisa ser autorizado de novo com calendar e tasks.
  Avise Renato; não tente autorizar pelo chat.
- "nenhum Python do Hermes": avise Renato com a mensagem de erro.
