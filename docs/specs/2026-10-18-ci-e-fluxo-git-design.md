# Jarvis — CI e fluxo Git (GitLab flow)

- **Data:** 2026-10-18
- **Status:** em revisão
- **Depende de:** [2026-10-17-jarvis-base-design.md](2026-10-17-jarvis-base-design.md) (o PR #1 precisa estar no `main`)

## 1. Objetivo

Adotar o **GitLab flow** com dois branches permanentes, `main` e `prod`. Nada chega à VPS sem passar por testes unitários, de validação de código e, principalmente, de segurança.

**Critério de sucesso:**
- Um commit só entra na VPS se todos os testes exigidos passaram **naquele commit** do `prod`.
- Os scripts de provisionamento são testados de verdade, numa VM descartável, antes de chegarem ao `prod`.

## 2. Decisões

| # | Decisão | Alternativas descartadas | Por quê |
|---|---|---|---|
| C1 | Branches de trabalho curtos (`feat/*`, `fix/*`) → PR para `main` → PR `main` → `prod` | Commits diretos no `main` | `main` sempre verde; cada mudança revisável |
| C2 | Deploy **manual** na VPS (`jarvis deploy`) | VPS busca sozinha; GitHub empurra via SSH | Você vê cada mudança entrar; nenhuma conexão de entrada |
| C3 | Continuar no **GitHub gratuito**; a trava fica na VPS | GitHub Pro (US$ 4/mês); migrar para GitLab.com | Repos privados no plano gratuito não têm proteção de branch (API: "Upgrade to GitHub Pro"). Os runners do GitHub são VMs completas, o que permite testar o provisionamento |
| C4 | Testes rápidos no PR para `main`; testes profundos (integração e auditoria) no PR e no push para `prod` | Tudo em todo PR | Feedback rápido no dia a dia; o custo maior só no lançamento |
| C5 | Ferramentas open source, versões fixas e checksum verificado | Ações de terceiros por tag | Cadeia de suprimentos do CI |
| C6 | Hooks locais: pre-commit (segredos + shellcheck) e **pre-push** (portão 1 local + recusa push direto em `main`/`prod`) | Só CI remoto | Erro descoberto em segundos; o hook faz o papel da proteção de branch que o GitHub gratuito não oferece |
| C7 | **Preflight** no início de cada script: valida variáveis e ambiente e lista todos os problemas **antes** de alterar qualquer coisa | Falhar no meio do script | Evita uma VPS meio configurada por causa de um valor errado em `vars.sh` |

## 3. Fluxo de branches

```
feat/x ──PR──► main ──PR (release: …)──► prod ──jarvis deploy──► VPS (/opt/jarvis)
fix/y  ──PR──┘
```

- **Trabalho:** `feat/<assunto>` ou `fix/<assunto>`, criado a partir do `main` → PR para `main` → portão 1 verde → merge (merge commit). O branch é apagado automaticamente (configuração do repo `delete_branch_on_merge`).
- **Lançamento:** PR `main` → `prod`, com título `release: <resumo>` → portão 2 verde → merge (merge commit) → `jarvis deploy` na VPS.
- **Correção urgente:** `fix/*` → `main` → `prod`. Nunca direto no `prod` (regra *upstream first*).
- **Garantia sem proteção de branch:** o job `origem` exige que **todo commit sem ser de merge alcançável a partir do `prod` exista no `main`**:
  ```
  git log --no-merges --format=%H origin/main..<commit-do-prod>   # precisa sair vazio
  ```
  Um push direto no `prod` deixa `origem` vermelho, e o `jarvis deploy` recusa.
- **Início:** o PR #1 entra no `main`; o `prod` é criado a partir do `main`; o `00-bootstrap.sh` passa a clonar com `-b prod`.

## 4. Portões de testes

### 4.1 Portão 1 — `.github/workflows/portao-1.yml`

Gatilhos: `pull_request` para `main` e `workflow_call`. No PR e no push para `prod`, ele roda só chamado pelo portão 2, para não rodar duas vezes.

| Job | Verifica | Ferramentas |
|---|---|---|
| `lint` | erros de bash, sintaxe, validade dos workflows | shellcheck, `bash -n`, actionlint |
| `unit` | `bats tests` (inclui `caddy validate` real via Docker e `visudo -cf`) | bats-core, Docker |
| `secrets` | nenhum segredo nos commits do evento (no PR, só os commits do PR) | gitleaks |
| `workflow-security` | ações fixadas por SHA, permissões mínimas, sem injeção de template | zizmor |

### 4.2 Portão 2 — `.github/workflows/portao-2.yml`

Gatilhos: `pull_request` para `prod`, e `push` em `prod`.

| Job | Verifica |
|---|---|
| `portao-1` | reutiliza o portão 1 |
| `origem` | a regra da seção 3. No PR, também exige que o branch de origem seja `main` |
| `secrets-historico` | gitleaks em todo o histórico |
| `integracao` | roda o provisionamento numa VM `ubuntu-24.04` descartável e audita o resultado (seção 4.3) |

### 4.3 Job `integracao`

1. Copia o checkout para `/opt/jarvis`, com dono igual ao usuário do runner (`ADMIN_USER=runner`).
2. Roda `00-bootstrap.sh` em **modo CI** (`JARVIS_CI=1`):
   - não pede senha;
   - não gera deploy key;
   - não clona (o repo já está em `/opt/jarvis`).
3. Roda `10` → `60`, sem pausa para interação:
   - o `30` lê a senha do dashboard de `JARVIS_DASHBOARD_PASSWORD` em modo CI;
   - o `40` recebe um `.env` com valores falsos.
4. **Auditoria.** Cada item é um teste bats em `tests/integracao/`, que roda só nesse job:
   - portas públicas: só `22/tcp` e `51820/udp` fora do loopback e de `10.8.0.1`;
   - `sshd -T`: `permitrootlogin no`, `passwordauthentication no`;
   - `hermes`:
     - `sudo -n true` falha;
     - `ls /opt/jarvis` falha;
     - `sudo jarvis-expose ../x 8100` e `sudo jarvis-expose Exemplo 8100` falham;
     - `sudo jarvis-expose exemplo 8101` funciona e o Caddy recarrega;
   - **ataque de link simbólico com o `hermes` real**: o `hermes` troca `~/.hermes/skills` por um link para `/usr/local/sbin`. `jarvis import` e `jarvis apply --force` precisam falhar, e o dono e o modo de `/usr/local/sbin` precisam ficar iguais;
   - API admin do Caddy: `curl localhost:2019` falha, e o socket `/run/caddy/admin.sock` é inacessível ao `hermes`;
   - **Docker rootless**: `docker run hello-world` como `hermes`, e `docker.service` de root inativo;
   - **Lynis**: `lynis audit system --quick`, com índice de endurecimento ≥ o valor em `ci/lynis-minimo.txt`. O relatório vai como artefato.
5. **Fora do escopo do CI:** conexão real com Telegram, OpenAI, Google e GitHub (não há segredos no CI). O `hermes-gateway` não é iniciado.

### 4.4 Testes exigidos pelo deploy

O arquivo `ci/testes-exigidos.txt` lista um nome de check run por linha:
- `lint`, `unit`, `secrets`, `workflow-security` (os nomes vindos de `workflow_call` são prefixados, por exemplo `portao-1 / lint`; o arquivo guarda o nome exato que a API devolve);
- `origem`, `secrets-historico`, `integracao`.

## 5. `jarvis deploy`

É um subcomando novo do `bin/jarvis`. Roda como admin, em `/opt/jarvis`.

1. `git fetch origin prod`. Se `HEAD` == `origin/prod`, mostra "nada novo" e sai com 0.
2. Lê a lista de testes exigidos **do `HEAD` local** (a versão já implantada), nunca do commit que está chegando.
3. Consulta `GET /repos/{GITHUB_SLUG}/commits/{sha}/check-runs` com o token de leitura. Cada nome exigido precisa existir, com `status: completed` e `conclusion: success`. Se faltar algum, ou se algum falhou ou ainda está rodando, sai com erro e lista quais.
4. Mostra `git log --oneline HEAD..sha` e `git diff --stat HEAD sha` e pede `s/N`.
5. `git merge --ff-only sha`. Se não for fast-forward, sai com erro: "histórico do prod foi reescrito; investigue".
6. Mapeia os caminhos alterados para as ações seguintes e **imprime** a lista:

| Caminho alterado | Ação sugerida |
|---|---|
| `hermes/**` | `jarvis apply` (o deploy oferece rodar, `s/N`) |
| `provision/10-*`, `system/apt/**`, `system/fail2ban/**`, `system/ssh/**` | `sudo provision/10-sistema.sh` |
| `provision/20-*`, `system/wireguard/**`, `bin/jarvis-peer` | `sudo provision/20-wireguard.sh` |
| `provision/30-*`, `system/dnsmasq/**`, `system/caddy/**`, `system/systemd/caddy-*`, `system/systemd/dnsmasq-*` | `sudo provision/30-dns-caddy.sh` |
| `provision/40-*`, `system/systemd/hermes-*` | `sudo provision/40-hermes.sh` |
| `provision/50-*`, `system/sudoers/**`, `bin/jarvis-expose` | `sudo provision/50-docker-rootless.sh` |
| `provision/60-*`, `system/systemd/jarvis-backup*`, `bin/jarvis-backup` | `sudo provision/60-backup.sh` |
| `provision/lib.sh`, `provision/vars.sh` | todos os scripts acima, em ordem |

   Scripts de root **não** são executados pelo deploy.

7. **Token:** `/home/<admin>/.config/jarvis/github-token`, com modo 600.
   - É fine-grained, só para o repo `renpv/jarvis`, com a permissão *Checks: read* (mais *Metadata: read*, obrigatória). Validade de 1 ano.
   - Se faltar ou for inválido, o deploy sai com erro e mostra como criar.
8. **Testável sem rede:** a URL da API (`GITHUB_API`) e o comando HTTP aceitam sobrescrita por variável de ambiente. Os testes bats usam um servidor falso (um script local que imprime JSON).

## 6. Ferramentas e manutenção

- **`ci/ferramentas.txt`:** uma linha por ferramenta, no formato `nome versão url sha256`. Cobre shellcheck, bats-core, gitleaks, actionlint, zizmor e lynis.
- **`ci/instalar-ferramentas.sh DIR`:** baixa cada ferramenta para `DIR`, confere o SHA-256 e **falha** se não bater. Roda igual no CI e no WSL.
- **Ações:** fixadas por SHA completo, com a versão num comentário. `.github/dependabot.yml` (ecossistema `github-actions`) roda semanalmente e abre PRs para o `main`.
- **Ferramentas de `ci/ferramentas.txt`:** revisão manual mensal (procedimento em `docs/aprendizado/80-ci-e-fluxo-git.md`).
- **Permissões:**
  - `permissions: contents: read` no topo de cada workflow; o job `integracao` também tem `actions: read` (para os artefatos);
  - nunca usar `pull_request_target`;
  - `persist-credentials: false` no checkout;
  - nenhum segredo no CI.
- **Lynis:** o primeiro run mede o índice e `ci/lynis-minimo.txt` começa 2 pontos abaixo da medida. Esse mínimo só sobe, nunca desce.

## 7. Paridade local

| Comando | O quê |
|---|---|
| `make test` | como hoje: lint + bats |
| `make ci` | portão 1 completo: `make test`, actionlint, zizmor e gitleaks no histórico local. Ferramentas ausentes ⇒ erro, com a instrução para instalar |
| `make hooks` | instala os dois hooks abaixo, versionados em `ci/hooks/` (o `core.hooksPath` aponta para lá; nada é copiado para `.git/hooks`) |

### 7.1 Pre-commit — `ci/hooks/pre-commit`

1. `gitleaks git --staged` (ou `gitleaks protect --staged`, conforme a versão fixada): bloqueia segredos no que está sendo commitado.
2. `shellcheck` nos `.sh` e nos arquivos de `bin/` do commit.
3. Ferramenta ausente ⇒ falha, com a instrução de instalação. Não passa em silêncio.

### 7.2 Pre-push — `ci/hooks/pre-push`

1. **Recusa push para `main` e `prod`.** O hook lê os refs de destino no stdin e aceita só `refs/heads/feat/*` e `refs/heads/fix/*`. Para os outros, mostra a mensagem "use um PR" e sai com 1.
2. **Roda `make ci`** (portão 1 completo) no commit que vai ser enviado. Se falhar, o push não acontece.
3. **Exceção consciente:** `git push --no-verify` pula o hook. O procedimento fica em `docs/aprendizado/80-ci-e-fluxo-git.md`, só para emergência. O CI e o `jarvis deploy` continuam valendo.
4. A lista de padrões permitidos fica numa variável no topo do hook (`ALLOWED_REFS`), coberta por teste.

## 8. Validação prévia (preflight)

**Objetivo:** nenhum script altera a máquina se alguma variável ou pré-condição estiver errada, e o usuário vê **todos** os problemas de uma vez.

### 8.1 Funções em `provision/lib.sh`

- `check_vars` — valida o `vars.sh`, acumula os erros numa lista e devolve quantos encontrou:

| Variável | Regra |
|---|---|
| `ADMIN_USER`, `HERMES_USER` | `^[a-z_][a-z0-9_-]{0,31}$`, diferentes entre si e diferentes de `root` |
| `HERMES_DIR`, `JARVIS_DIR` | caminho absoluto, sem `..` e sem espaço |
| `GITHUB_SLUG` | `^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$` |
| `GITHUB_REPO` | começa com `git@github.com:` ou `https://github.com/` |
| `TIMEZONE` | existe `/usr/share/zoneinfo/$TIMEZONE` |
| `DOMAIN` | rótulos DNS válidos, com pelo menos um ponto |
| `WG_IF` | `^[a-z][a-z0-9]{0,14}$` |
| `WG_PORT`, `DASHBOARD_PORT`, `APP_PORT_MIN`, `APP_PORT_MAX` | inteiros de 1 a 65535, com `APP_PORT_MIN < APP_PORT_MAX` e `DASHBOARD_PORT` fora da faixa de apps |
| `WG_NET` | três octetos válidos, ex.: `10.8.0` |
| `WG_SERVER_IP` | IPv4 válido dentro de `WG_NET.0/24` |
| `WG_ENDPOINT` | vazio ou IPv4/nome DNS válido |

- `check_env_os` — confere `ID=ubuntu` e `VERSION_ID=24.04` em `/etc/os-release`. O caminho aceita sobrescrita para os testes.
- `check_commands CMD...` — lista os comandos ausentes.
- `preflight [REQUISITOS...]` — chama `check_vars`, mais os requisitos do script, e **morre listando todos os problemas** se houver algum. Requisitos:
  - `os`
  - `root`
  - `sudo-admin` (rodando com sudo pelo `ADMIN_USER`)
  - `cmd:<nome>`
  - `ci-env:<VAR>` (exigida só em modo CI)
  - `iface:<if>` (interface com o IP esperado)
  - `user:<nome>` (usuário existe)

### 8.2 Uso em cada script (primeira linha útil, antes de qualquer alteração)

| Script | Requisitos |
|---|---|
| `00-bootstrap.sh` | `os root` |
| `10-sistema.sh` | `os root sudo-admin` (e `authorized_keys` do admin não vazio) |
| `20-wireguard.sh` | `os root` |
| `30-dns-caddy.sh` | `os root iface:$WG_IF ci-env:JARVIS_DASHBOARD_PASSWORD` |
| `40-hermes.sh` | `os root` |
| `50-docker-rootless.sh` | `os root user:$HERMES_USER` |
| `60-backup.sh` | `os root user:$HERMES_USER` |
| `jarvis deploy` | `check_vars`, mais: repo git em `JARVIS_DIR`, token legível com modo 600, `cmd:curl cmd:jq cmd:git` |
| `jarvis apply`/`import`/`diff` | `check_vars`, mais `user:$HERMES_USER` (fora dos testes) |

### 8.3 `jarvis check`

Roda `check_vars`, o SO, os comandos esperados, `jarvis check-env` e a existência do token de deploy. Mostra ✅/❌ por item, **não altera nada** e sai com 0 só se tudo passar.

### 8.4 Testes

`tests/preflight.bats` traz um teste por regra da tabela 8.1, com um valor inválido. Também cobre:
- vários erros juntos aparecem todos na saída;
- `preflight` falha **antes** de qualquer efeito (verificado com um script de teste que cria um arquivo-sentinela depois do preflight, e o arquivo não aparece).

## 9. Custos e limites

- **Minutos de Actions:** o plano gratuito tem 2.000 min/mês em repos privados. Estimativa: ~250 min/mês (40 × 3 min + 8 × 15 min).
- **Integração:** a VM do runner difere da VPS real (kernel, rede). Um job `integracao` verde **não substitui** as verificações da Fase B; ele pega regressões nos scripts.

## 10. Riscos

| Risco | Mitigação |
|---|---|
| Merge com teste vermelho (o GitHub gratuito não bloqueia) | `jarvis deploy` não traz commit sem todos os checks exigidos verdes |
| Push direto no `prod` | job `origem` fica vermelho → deploy recusa |
| Commit que remove exigências do próprio CI | o deploy lê `testes-exigidos.txt` do `HEAD` já implantado |
| Ação ou ferramenta comprometida | fixação por SHA e checksum; zizmor; Dependabot; permissões mínimas; sem segredos no CI |
| Token de leitura vazado | só lê resultados de testes de um repo; fica fora do alcance do `hermes` |
| `integracao` instável (rede, espelhos do apt) | um re-run manual é permitido; falha persistente é tratada como bug |
| Diferença entre a VM do runner e a VPS | documentada; a Fase B continua obrigatória |
| Valor errado em `vars.sh` deixa a VPS meio configurada | `preflight` valida tudo antes de qualquer alteração |
| Push direto em `main`/`prod` por engano | hook pre-push recusa; se for pulado com `--no-verify`, o CI e o deploy ainda barram |

## 11. Critérios de aceite

1. Um PR para `main` com um `.sh` com erro de shellcheck fica vermelho em `lint`.
2. Um PR com um token falso num arquivo fica vermelho em `secrets`.
3. Um workflow com ação por tag (não por SHA) fica vermelho em `workflow-security`.
4. Um PR para `prod` vindo de um branch que não é o `main` fica vermelho em `origem`.
5. O job `integracao` roda `00` → `60` na VM, e toda a auditoria da seção 4.3 passa, inclusive o ataque de link simbólico com o `hermes` real.
6. Na VPS, `jarvis deploy` com o commit do `prod` com checks verdes avança e sugere as ações certas. Com algum check vermelho ou ausente, recusa sem alterar o `HEAD`.
7. `make hooks` instalado: um `git commit` contendo um token falso é bloqueado localmente.
8. O Dependabot abre um PR de atualização de ação, e ele passa pelo portão 1.
9. `make hooks` instalado: `git push origin main` é recusado localmente com a mensagem "use um PR"; `git push` de um `feat/*` com teste quebrado é recusado; com tudo verde, passa.
10. Com `TIMEZONE=America/Fortalesa` e `WG_PORT=99999` no `vars.sh`, qualquer script de `provision/` sai com erro listando **os dois** problemas, sem alterar nada na máquina.
11. `jarvis check` numa VPS saudável mostra tudo ✅ e sai com 0. Sem o token de deploy, mostra ❌ nesse item e sai com 1.
