# Como o Hermes funciona

Este guia explica as peças do Hermes Agent que o Jarvis usa. Tudo aqui vem da documentação
oficial (<https://hermes-agent.nousresearch.com/docs/>); os links apontam para a página de origem.
Os guias seguintes (`10-…` a `70-…`) mostram cada peça funcionando na VPS.

## 1. O ciclo do agente

Cada mensagem que você manda segue o mesmo ciclo:

1. **Chega a mensagem** — pelo Telegram, pelo dashboard ou pelo terminal (`hermes chat`).
2. **O Hermes monta o prompt de sistema.** Em ordem, três camadas
   ([prompt assembly](https://hermes-agent.nousresearch.com/docs/developer-guide/prompt-assembly)):
   - **estável:** a identidade (`SOUL.md`) e as orientações sobre ferramentas e modelo;
   - **contexto:** arquivos de projeto da pasta atual (`AGENTS.md`, `.hermes.md`…), se houver;
   - **volátil:** o índice de skills, a memória (`MEMORY.md`, `USER.md`), data/hora, modelo e ambiente.
3. **O LLM decide:** responder direto ou pedir uma ou mais **ferramentas** (rodar um comando,
   ler um arquivo, buscar na web, abrir uma skill…).
4. **As ferramentas executam** e o resultado volta para o LLM.
5. **Repete** os passos 3–4 até o LLM produzir a resposta final, que vai para você.

O LLM (no nosso caso, um modelo da OpenAI) só "pensa". Quem executa é o Hermes, na VPS,
como o usuário `hermes` — por isso as permissões desse usuário são a fronteira de segurança real.

## 2. Ferramentas e o terminal

As ferramentas vêm agrupadas em *toolsets* (terminal, arquivos, web, skills, memória, cron…).
A mais poderosa é o **terminal**, que tem *backends*
([tools](https://hermes-agent.nousresearch.com/docs/user-guide/features/tools)):

| Backend | Onde o comando roda | Checagem de comando perigoso |
|---|---|---|
| `local` | na própria máquina, como o usuário do Hermes | sim |
| `docker` | dentro de um container | não (o container é a barreira) |
| `ssh` | em outra máquina | sim |

O Jarvis usa **`local`**: ele precisa enxergar a VPS para monitorar serviços e publicar apps.
A proteção vem de três lugares: o usuário `hermes` não tem sudo (exceto `jarvis-expose`),
as **aprovações** e a lista **deny**.

## 3. Aprovações

Com `approvals.mode: manual`, todo comando que o Hermes classifica como perigoso (ex.: `rm -rf`)
espera sua aprovação. No Telegram, aparecem botões **Aprovar / Negar** (ou `/approve`, `/deny`).
Se ninguém responder em `approvals.timeout` segundos, o comando é **negado** ("falha fechado").

A lista `approvals.deny` é diferente: são padrões que **nunca** rodam, nem com aprovação,
nem no modo `/yolo`. Ex.: `git push --force*`, `*curl*|*sh*`.

## 4. Skills

Uma skill é uma pasta com um `SKILL.md`: frontmatter (`name`, `description`, …) e instruções
em Markdown ([skills](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills)).

O Hermes não carrega todas as skills inteiras no prompt. Ele usa **divulgação progressiva**:

- nível 0 — só a lista (nome + descrição) entra no prompt;
- nível 1 — quando a tarefa pede, o agente abre a skill inteira (`skill_view`);
- nível 2 — se precisar, abre um arquivo de referência dentro dela.

Por isso a **descrição** de uma skill importa tanto: é por ela que o agente decide abri-la.

Tipos de skill no Jarvis:
- **nativas** — vêm com o Hermes (ex.: `github`, `google-workspace`);
- **nossas** — em `~/.hermes/skills/jarvis/` (`publicar-app`, `tarefas`, `monitorar-vps`),
  versionadas no repo em `hermes/skills/jarvis/`;
- **criadas pelo agente** — o Hermes pode escrever skills novas quando aprende um procedimento.

## 5. Memória

Dois arquivos em `~/.hermes/memories/`
([memory](https://hermes-agent.nousresearch.com/docs/user-guide/features/memory)):

| Arquivo | Conteúdo | Limite |
|---|---|---|
| `MEMORY.md` | notas do agente: fatos do ambiente, convenções, coisas aprendidas | ~2.200 caracteres |
| `USER.md` | seu perfil: preferências, estilo, expectativas | ~1.375 caracteres |

Pontos importantes:
- A memória entra no prompt como uma **foto tirada no início da sessão**. O que o agente salva
  no meio da conversa vai para o disco na hora, mas só aparece no prompt na **próxima** sessão.
- Só é memória o que o agente gravou com a ferramenta `memory`. Se ele disser "anotei" e não
  estiver no arquivo, ele não anotou. Confira: `sudo cat /var/lib/hermes/.hermes/memories/MEMORY.md`.
- Memória é **estado** (vai no backup), não configuração (não vai para o Git).

## 6. Gateway

O gateway é **um processo** (`hermes gateway run`, nosso serviço `hermes-gateway`) que conecta
o Hermes às plataformas de mensagem
([messaging](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/)).

- No **Telegram**, ele faz *polling*: é o Hermes que pergunta ao Telegram se há mensagens novas.
  Por isso não há nenhuma porta aberta na VPS para o Telegram.
- Cada chat vira uma **sessão** com histórico próprio.
- `TELEGRAM_ALLOWED_USERS` define quem pode falar com o bot. Os demais são ignorados.
- O gateway também roda o **cron** e entrega os pedidos de **aprovação**.

## 7. Cron (rotinas)

Jobs agendados ficam em `~/.hermes/cron/` e são criados com `hermes cron create`
(ou pedindo ao próprio Jarvis):

```bash
jarvis hermes cron create "0 7 * * *" "Resumo do dia…" --name "Resumo matinal" --deliver telegram
jarvis hermes cron list
```

O horário segue a chave `timezone` do `config.yaml` (no Jarvis, `America/Fortaleza`).
Cron jobs são **estado** (vão no backup), não vão para o Git — os comandos de criação ficam
documentados em `70-integracoes.md`.

## 8. Dashboard

`hermes dashboard` é uma interface web com abas de configuração, sessões, cron, skills, canais
e uma aba **Chat**, que é o próprio TUI do Hermes rodando no navegador.

O dashboard guarda chaves de API, então ele escuta só em `127.0.0.1:9119`. Você chega nele por
`http://hermes.jarvis.lan`, com a VPN ligada: o Caddy pede usuário e senha e repassa para o
dashboard.

Mudanças feitas pelo dashboard alteram arquivos do Hermes (ex.: `config.yaml`). É para isso que
existe o `jarvis diff`.

## 9. O mapa de `~/.hermes`

No Jarvis, `~` do Hermes é `/var/lib/hermes`.

| Caminho | O que é | Tipo no Jarvis |
|---|---|---|
| `config.yaml` | configurações (modelo, terminal, aprovações, fuso…) | **declarativo** → repo |
| `SOUL.md` | identidade/personalidade | **declarativo** → repo |
| `skills/jarvis/` | nossas skills | **declarativo** → repo |
| `.env` | chaves de API e tokens | **segredo** → só na VPS |
| `auth.json` | credenciais OAuth de provedores | **segredo** → só na VPS |
| `memories/` | memória | **estado** → backup |
| `skills/` (resto) | skills nativas e criadas pelo agente | **estado** → backup |
| `cron/` | rotinas | **estado** → backup |
| `sessions/`, `state.db` | conversas e banco | **estado** → backup |
| `logs/` | logs (segredos mascarados) | descartável |

## 10. Como o Jarvis organiza isso

Quatro lugares (veja a spec, seção 4):

```
① computador ──push──► ② GitHub ──pull──► ③ /opt/jarvis ──jarvis apply──► ④ /var/lib/hermes/.hermes
                                              ▲                                   │
                                              └──────────jarvis import────────────┘
```

- `jarvis apply` — copia o declarativo de ③ para ④ e reinicia o Hermes. **Recusa** se o Hermes
  mudou algo que você ainda não trouxe para o repo.
- `jarvis diff` — mostra a diferença entre ③ e ④.
- `jarvis import` — traz as mudanças de ④ para ③ (e **aborta** se achar algo parecido com um token).

## 11. Exercícios (depois da instalação, Tarefa 14)

1. Leia o `config.yaml` padrão que o instalador criou (`hermes/config.yaml` no repo, primeiro commit).
   Encontre: o modelo, o backend do terminal, as aprovações.
2. Mude uma opção pelo dashboard e rode `jarvis diff`. Depois decida: `jarvis import` ou `jarvis apply --force`.
3. Pergunte ao Jarvis: "o que você tem na sua memória sobre mim?" e compare com
   `sudo cat /var/lib/hermes/.hermes/memories/USER.md`.
4. Peça ao Jarvis para listar as skills dele e explicar quando usaria a `publicar-app`.
