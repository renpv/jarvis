---
name: lancamento
description: Use when Renato pede para abrir um lançamento, levar o main para o prod, fazer deploy na VPS do Jarvis, ou quando PRs foram mesclados no main e precisam chegar à VPS
---

# Lançamento (main → prod → VPS)

## Visão geral
Fluxo GitLab flow do repo `renpv/jarvis`: PRs entram no `main`, um PR de lançamento leva o `main`
ao `prod`, e o `jarvis deploy` traz o `prod` para `/opt/jarvis` na VPS. Referência: `docs/aprendizado/80-ci-e-fluxo-git.md`.

**Quem faz o quê:** os merges são do Renato (o Claude Code bloqueia merge sem revisão). Comandos
com sudo na VPS só com a regra temporária ativa (`sudo -n true`); sem ela, passe o comando ao Renato.

## Passos
1. **Conferir o que vai:** `git fetch origin && git log --oneline --first-parent origin/prod..origin/main`.
   Se estiver vazio, não há lançamento.
2. **Abrir o PR** `--base prod --head main`, com título `release: …`. O corpo lista cada PR (`#N: o que muda`)
   e diz o que rodar depois: só `jarvis deploy`; `+ jarvis apply` se `hermes/` mudou; `+ sudo provision/NN-*.sh` se o script ou o arquivo de `system/` dele mudou.
3. **Acompanhar o portão 2 do PR** em segundo plano (`gh run list --workflow portao-2.yml --event pull_request`)
   e avisar o Renato quando ficar verde, para ele mesclar.
4. **Acompanhar o portão 2 do push no `prod`**, filtrando pelo `headSha` do `origin/prod` novo.
   O `jarvis deploy` só aceita essa execução.
5. **Deploy com prévia:** `ssh jarvis 'cd /opt/jarvis && echo n | jarvis deploy'`. Confirme que a lista de
   commits é exatamente a do PR. Só então `echo s | jarvis deploy`.
6. **Se `hermes/` mudou:** `jarvis diff` e depois `jarvis apply`. Se o apply recusar ("o Hermes tem mudanças"),
   leia o diff. Ele mostra repo × Hermes, não base × Hermes: o que recusa o apply é o que mudou no Hermes desde o último apply ou import.
   - Mudança do Hermes que vale guardar (estado, lição numa skill): leve ao repo por PR antes de aplicar.
   - Só sobrou o próprio lançamento: `jarvis apply --force`.
7. **Conferir:** `jarvis diff` limpo, `systemctl is-active hermes-gateway hermes-dashboard`. Se o
   sudo temporário foi renovado só para isso, remova `/etc/sudoers.d/90-claude-temporario`.

## Erros comuns
| Situação | O que fazer |
|---|---|
| `deploy` diz "há mudanças locais em /opt/jarvis" | Alguém rodou `jarvis import`. Mostre o `git status` e o `git diff` ao Renato. O que é do Hermes vai por PR; o descarte (`git checkout`) é dele. |
| `jarvis import` no lugar do `apply` depois de um deploy | Desde 2026-10-24 o import faz mescla de três vias também nas skills e não desfaz o deploy. Confira com `git status`. |
| `command_allowlist` aparece no `config.yaml` do Hermes | É um "Sempre permitir" clicado no Telegram. Não leve ao repo sem o Renato decidir. |
| Arquivo `__pycache__`/`.pyc` no diff | Não versione (`.gitignore`). Scripts de skill rodam com `python -B`. |
| `gh` falha com "error connecting" | DNS do Windows (outra VPN). `git` pode usar `HostName` = IP do GitHub com `HostKeyAlias=github.com`; o `gh` precisa do DNS de volta. |
| Pre-push recusa o branch | Só `feat/*` ou `fix/*`. |
