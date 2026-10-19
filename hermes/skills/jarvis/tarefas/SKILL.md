---
name: tarefas
description: Gerencia a lista de tarefas de Renato no arquivo /var/lib/hermes/notas/tarefas.md
version: 1.0.0
author: Renato e Jarvis
platforms: [linux]
metadata:
  hermes:
    tags: [produtividade, tarefas, jarvis]
---

# Tarefas

## Quando usar
Quando Renato pedir para anotar, listar, concluir, adiar ou apagar tarefas ("me lembra de...",
"o que tenho pendente?", "marquei X como feito").
Lembrete com hora marcada ("me avisa amanhã às 15h") é cron, não tarefa — use o cron do Hermes,
com entrega no Telegram, e também anote a tarefa se fizer sentido.

## Arquivo
`/var/lib/hermes/notas/tarefas.md` — crie com o modelo abaixo se não existir.

```markdown
# Tarefas

## Pendentes
- [ ] 2026-10-20 · Pagar a conta de luz #casa
- [ ] sem data · Ler o artigo sobre WireGuard #estudo

## Concluídas
- [x] 2026-10-15 · Renovar token do GitHub #jarvis (feita 2026-10-16)
```

## Formato
- Uma tarefa por linha: `- [ ] AAAA-MM-DD · descrição #etiqueta` (ou `sem data`).
- Pendentes ordenadas por data (sem data no fim).
- Ao concluir: mova para "Concluídas", troque `[ ]` por `[x]` e acrescente `(feita AAAA-MM-DD)`.
- Datas relativas ("sexta", "amanhã") viram data absoluta no fuso America/Fortaleza.

## Procedimento
1. Leia o arquivo inteiro antes de mudar.
2. Faça a mudança preservando o resto do arquivo.
3. Confirme para Renato em uma linha o que mudou.

## Verificação
`grep -n "<trecho da tarefa>" /var/lib/hermes/notas/tarefas.md` mostra a linha esperada.
