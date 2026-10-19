# CI e fluxo Git — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para implementar este plano tarefa por tarefa. Os passos usam checkbox (`- [ ]`) para acompanhamento.

**Objetivo:** GitLab flow com `main` e `prod`. Testes unitários, de validação e de segurança rodam no GitHub Actions. Hooks locais pre-commit/pre-push. Preflight de variáveis em todo script. E o `jarvis deploy`, que só traz para a VPS commits do `prod` com todos os testes verdes.

**Arquitetura:**
- **Portão 1** (`portao-1.yml`: lint, unit, secrets, workflow-security) em PRs para o `main`.
- **Portão 2** (`portao-2.yml`: portão 1 + origem, secrets-historico e a integração em VM descartável) em PRs e pushes para o `prod`.
- **Trava:** como o GitHub gratuito não protege branches, ela fica na VPS (`jarvis deploy` consulta a API de check-runs) e na máquina local (hook pre-push).

**Tecnologias:** GitHub Actions, bash, bats-core, shellcheck, actionlint, zizmor, gitleaks, Lynis, jq, curl.

**Spec:** [docs/specs/2026-10-18-ci-e-fluxo-git-design.md](../specs/2026-10-18-ci-e-fluxo-git-design.md). Base: [2026-10-17-jarvis-base-design.md](../specs/2026-10-17-jarvis-base-design.md).

## Restrições globais

- Branches permanentes: `main` e `prod`. Trabalho em `feat/<assunto>` ou `fix/<assunto>` (regex `^refs/heads/(feat|fix)/[a-z0-9._-]+$`).
- Runner: `ubuntu-24.04`. Permissões: `contents: read` no topo de cada workflow. Nunca `pull_request_target`. Checkout com `persist-credentials: false`. **Nenhum segredo no CI.**
- Ações fixadas por SHA completo:
  - `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1` (v7.0.1)
  - `actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` (v7.0.1)
- Ferramentas (versão, URL e SHA-256 conferidos em 2026-10-19):

| nome | versão | sha256 |
|---|---|---|
| shellcheck | 0.11.0 | `8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198` |
| bats | 1.14.0 | `bb537b70b15b732f6d8827dd6578e3d8ce166636ce1f18ea9a074184fcce9177` |
| gitleaks | 8.30.1 | `551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb` |
| actionlint | 1.7.12 | `8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8` |
| zizmor | 1.30.1 | `e65324f4430c2717591937edcec90ccbefaf14c174f8ec9415e03ca875b46e1a` |
| lynis | 3.1.7 | `48d829d0dc2c583a3e838cc09a7190b69a3af844bcb913c7cf9c0226b04b95c5` |

- Nomes dos check runs exigidos pelo deploy:
  - `portao-1 / lint`, `portao-1 / unit`, `portao-1 / secrets`, `portao-1 / workflow-security`
  - `origem`, `secrets-historico`, `integracao`
- O deploy lê `ci/testes-exigidos.txt` **do `HEAD` local**, nunca do commit que está chegando.
- O preflight lista **todos** os problemas e sai com 1 **antes** de qualquer alteração.
- Token de deploy: `$HOME/.config/jarvis/github-token`, modo 600, fine-grained, só `renpv/jarvis`, *Checks: read*.

## Foco de revisão

1. **Check run repetido:** o mesmo nome aparece várias vezes por causa de re-runs. O deploy usa o **mais recente** (`started_at`): um re-run verde depois de um vermelho libera, e um re-run vermelho depois de um verde bloqueia. O teste fica na Tarefa 5.
2. **Pre-push enviando um ref diferente do `HEAD`, ou com a árvore suja.** O `make ci` testaria outra coisa. O esperado é recusar e pedir checkout/commit. O teste fica na Tarefa 7.
3. **Deploy com o `/opt/jarvis` fora do `prod` ou com mudanças locais**, como depois de um `jarvis import` que ainda não virou PR. O esperado é recusar sem tocar em nada e explicar o caminho. O teste fica na Tarefa 5.
4. **Instalador de ferramentas interrompido no meio**, deixando um download parcial. O esperado é que a próxima execução baixe de novo e confira o checksum, nunca usando um arquivo sem o marcador `.ok`. O teste fica na Tarefa 1.
5. **Valores-limite no preflight:** porta 65535 vs 65536, `WG_SERVER_IP` com o último octeto 255 e `DASHBOARD_PORT` igual a `APP_PORT_MIN`. O esperado é aceitar ou recusar exatamente conforme a tabela 8.1 da spec. O teste fica na Tarefa 2.

---

## Mapa de arquivos

```
.github/
├── workflows/portao-1.yml       lint · unit · secrets · workflow-security
├── workflows/portao-2.yml       portao-1 (reuso) · origem · secrets-historico · integracao
└── dependabot.yml               ações, semanal, cooldown
ci/
├── ferramentas.txt              nome versão url sha256 binário-no-tar
├── instalar-ferramentas.sh      baixa, confere SHA-256, extrai em DIR/opt e liga em DIR/bin
├── origem.sh                    regra do GitLab flow (prod ⊆ main)
├── integracao.sh                00→60 duas vezes + auditoria + Lynis (só no CI)
├── testes-exigidos.txt          check runs exigidos pelo deploy
├── lynis-minimo.txt             índice mínimo
└── hooks/pre-commit, hooks/pre-push
provision/lib.sh                 + check_vars, check_os, preflight, apt_get
provision/00…60                  + preflight; modo CI (00, 30); Docker do 50 robusto
bin/jarvis                       + check, deploy; preflight em apply/import/diff
tests/
├── helpers.bash                 + identidade git para commits de teste
├── ferramentas.bats  preflight.bats  check.bats  deploy.bats  origem.bats  hooks.bats  workflows.bats
└── integracao/auditoria.bats    (só no job integracao; `bats tests` não entra em subpastas)
docs/aprendizado/80-ci-e-fluxo-git.md, docs/operacao.md, README.md, docs/plans/2026-10-17-jarvis-base.md (Fase B)
Makefile                         + ci, ferramentas, hooks; lint cobre ci/
.gitignore                       + .ci-bin/
```

---

# FASE A — no computador (branch `feat/ci-fluxo-git`)

### Tarefa 0: Pré-requisito: código base no `main`

**Arquivos:** nenhum.

- [ ] **Passo 1 [RENATO]: fazer o merge do PR renpv/jarvis#1** no GitHub (botão "Merge pull request", tipo *merge commit*).

- [ ] **Passo 2: rebasear o branch deste trabalho**

```bash
cd ~/dev/jarvis
GIT_SSH_COMMAND="ssh -F /dev/null -i $HOME/.ssh/id_renpv -o IdentitiesOnly=yes" git fetch origin
git switch feat/ci-fluxo-git && git rebase origin/main
git switch -C main origin/main && git switch feat/ci-fluxo-git
make test
```

Esperado: `make test` passa, com o mesmo total de testes do PR #1 (67). Se o `~/.ssh/config` já tiver sido corrigido (veja a nota no fim do plano), dispense o `GIT_SSH_COMMAND`.

---

### Tarefa 1: Ferramentas fixadas por checksum

**Arquivos:**
- Criar: `ci/ferramentas.txt`, `ci/instalar-ferramentas.sh`, `tests/ferramentas.bats`
- Modificar: `Makefile`, `.gitignore`, `tests/helpers.bash`

**Interfaces:**
- Produz `ci/instalar-ferramentas.sh DIR [NOME...]`, que instala em `DIR/opt/<nome>-<versão>/` e liga em `DIR/bin/<nome>`. Sem `NOME`, instala tudo.
- Ambiente aceito: `FERRAMENTAS_LIST` (padrão `ci/ferramentas.txt`) e `JARVIS_FETCH` (padrão `curl -fsSL -o`; recebe `ARQUIVO URL`).
- Marcador de instalação completa: `DIR/opt/<nome>-<versão>/.ok`.

- [ ] **Passo 1: identidade git nos testes.** Acrescentar ao fim de `tests/helpers.bash`:

```bash
# Commits feitos pelos testes (repos temporários) não dependem da configuração do usuário.
export GIT_AUTHOR_NAME=teste GIT_AUTHOR_EMAIL=teste@exemplo.invalid
export GIT_COMMITTER_NAME=teste GIT_COMMITTER_EMAIL=teste@exemplo.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
```

- [ ] **Passo 2: escrever os testes que falham, `tests/ferramentas.bats`**

```bash
load helpers

setup() {
  make_sandbox
  mkdir -p "$SANDBOX/src/foo-1.0" "$SANDBOX/files"
  printf '#!/bin/sh\necho foo-ok\n' > "$SANDBOX/src/foo-1.0/foo"
  chmod +x "$SANDBOX/src/foo-1.0/foo"
  tar -C "$SANDBOX/src" -czf "$SANDBOX/files/foo-1.0.tar.gz" foo-1.0
  sha=$(sha256sum "$SANDBOX/files/foo-1.0.tar.gz" | cut -d' ' -f1)
  printf '# teste\nfoo 1.0 https://github.com/x/foo/foo-1.0.tar.gz %s foo-1.0/foo\n' "$sha" > "$SANDBOX/lista.txt"
  cat > "$SANDBOX/fetch" <<EOF
#!/usr/bin/env bash
echo "\$2" >> "$SANDBOX/fetch.log"
cp "$SANDBOX/files/\$(basename "\$2")" "\$1"
EOF
  chmod +x "$SANDBOX/fetch"
  export FERRAMENTAS_LIST="$SANDBOX/lista.txt" JARVIS_FETCH="$SANDBOX/fetch"
  INST="$REPO_ROOT/ci/instalar-ferramentas.sh"
}

@test "instala, confere o checksum e liga o binário em DIR/bin" {
  run "$INST" "$SANDBOX/dest"
  [ "$status" -eq 0 ]
  [ "$("$SANDBOX/dest/bin/foo")" = foo-ok ]
  [ -f "$SANDBOX/dest/opt/foo-1.0/.ok" ]
}

@test "checksum errado aborta e não deixa binário instalado" {
  sed -i 's/ [0-9a-f]\{64\} / 0000000000000000000000000000000000000000000000000000000000000000 /' "$SANDBOX/lista.txt"
  run "$INST" "$SANDBOX/dest"
  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum"* ]]
  [ ! -e "$SANDBOX/dest/bin/foo" ]
}

@test "segunda execução não baixa de novo" {
  "$INST" "$SANDBOX/dest"
  "$INST" "$SANDBOX/dest"
  [ "$(wc -l < "$SANDBOX/fetch.log")" -eq 1 ]
}

@test "instalação interrompida (sem .ok) é refeita com checksum" {
  "$INST" "$SANDBOX/dest"
  rm "$SANDBOX/dest/opt/foo-1.0/.ok"
  echo lixo > "$SANDBOX/dest/opt/foo-1.0/foo"
  run "$INST" "$SANDBOX/dest"
  [ "$status" -eq 0 ]
  [ "$("$SANDBOX/dest/bin/foo")" = foo-ok ]
  [ "$(wc -l < "$SANDBOX/fetch.log")" -eq 2 ]
}

@test "instala só as ferramentas pedidas" {
  printf 'bar 2.0 https://github.com/x/bar/bar.tar.gz %s bar/bar\n' "$(printf '0%.0s' {1..64})" >> "$SANDBOX/lista.txt"
  run "$INST" "$SANDBOX/dest" foo
  [ "$status" -eq 0 ]
  [ -e "$SANDBOX/dest/bin/foo" ]
  [ ! -e "$SANDBOX/dest/bin/bar" ]
}

@test "ci/ferramentas.txt real: 5 campos, URL do GitHub, sha256 de 64 hex" {
  while read -r nome versao url sha bin; do
    [[ -z $nome || $nome == \#* ]] && continue
    [[ -n $bin ]] || { echo "campos faltando: $nome"; return 1; }
    [[ $url == https://github.com/* ]] || { echo "url: $nome"; return 1; }
    [[ $sha =~ ^[0-9a-f]{64}$ ]] || { echo "sha: $nome"; return 1; }
  done < "$REPO_ROOT/ci/ferramentas.txt"
  for n in shellcheck bats gitleaks actionlint zizmor lynis; do
    grep -q "^$n " "$REPO_ROOT/ci/ferramentas.txt" || { echo "faltando: $n"; return 1; }
  done
}
```

- [ ] **Passo 3: rodar e ver falhar**

Rode: `bats tests/ferramentas.bats`
Esperado: FAIL, porque o script e a lista não existem.

- [ ] **Passo 4: criar `ci/ferramentas.txt`**

```
# nome versão url sha256 binário-dentro-do-tar
# Conferidos em 2026-10-19. Para atualizar: docs/aprendizado/80-ci-e-fluxo-git.md, seção "Atualizar ferramentas".
shellcheck 0.11.0 https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz 8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198 shellcheck-v0.11.0/shellcheck
bats 1.14.0 https://github.com/bats-core/bats-core/archive/refs/tags/v1.14.0.tar.gz bb537b70b15b732f6d8827dd6578e3d8ce166636ce1f18ea9a074184fcce9177 bats-core-1.14.0/bin/bats
gitleaks 8.30.1 https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz 551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb gitleaks
actionlint 1.7.12 https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz 8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 actionlint
zizmor 1.30.1 https://github.com/zizmorcore/zizmor/releases/download/v1.30.1/zizmor-x86_64-unknown-linux-gnu.tar.gz e65324f4430c2717591937edcec90ccbefaf14c174f8ec9415e03ca875b46e1a zizmor
lynis 3.1.7 https://github.com/CISOfy/lynis/archive/refs/tags/3.1.7.tar.gz 48d829d0dc2c583a3e838cc09a7190b69a3af844bcb913c7cf9c0226b04b95c5 lynis-3.1.7/lynis
```

- [ ] **Passo 5: criar `ci/instalar-ferramentas.sh`**

```bash
#!/usr/bin/env bash
# instalar-ferramentas — instala as ferramentas de ci/ferramentas.txt em DIR, conferindo o SHA-256.
#   ci/instalar-ferramentas.sh DIR [NOME...]     (sem NOME: todas)
# Cada ferramenta vai para DIR/opt/<nome>-<versão>/ e o binário é ligado em DIR/bin/<nome>.
# Checksum diferente do registrado = aborta. Mesmo script no CI e no seu computador.
set -euo pipefail

dest=${1:?uso: ci/instalar-ferramentas.sh DIR [NOME...]}
shift
list=${FERRAMENTAS_LIST:-$(dirname "$(readlink -f "$0")")/ferramentas.txt}
read -r -a fetch <<<"${JARVIS_FETCH:-curl -fsSL -o}"

die() { echo "instalar-ferramentas: $*" >&2; exit 1; }

wanted() {
  (($# == 0)) && return 0
  local n=$1
  shift
  local w
  for w in "${WANTED[@]}"; do [[ $w == "$n" ]] && return 0; done
  return 1
}

WANTED=("$@")
mkdir -p "$dest/bin" "$dest/opt" "$dest/cache"

while read -r name version url sha bin; do
  [[ -z ${name:-} || $name == \#* ]] && continue
  if ((${#WANTED[@]})) && ! wanted "$name" x; then continue; fi
  target="$dest/opt/$name-$version"
  if [[ ! -f $target/.ok ]]; then
    file="$dest/cache/$name-$version-$(basename "$url")"
    rm -f "$file"
    "${fetch[@]}" "$file" "$url" || die "download falhou: $url"
    if ! echo "$sha  $file" | sha256sum -c --quiet - >/dev/null 2>&1; then
      rm -f "$file"
      die "checksum NÃO confere para $name $version — nada foi instalado"
    fi
    rm -rf "$target"
    mkdir -p "$target"
    tar -xf "$file" -C "$target"
    [[ -x $target/$bin ]] || die "binário não encontrado no pacote: $bin"
    touch "$target/.ok"
  fi
  ln -sfn "../opt/$name-$version/$bin" "$dest/bin/$name"
  echo "ok $name $version"
done <"$list"
```

Depois: `chmod +x ci/instalar-ferramentas.sh`

- [ ] **Passo 6: rodar e ver passar**

Rode: `bats tests/ferramentas.bats && shellcheck -x ci/instalar-ferramentas.sh`
Esperado: 6/6 passam e o lint fica limpo.

- [ ] **Passo 7: `Makefile` e `.gitignore`.** Substituir o `Makefile` inteiro por:

```make
# Makefile
#   make test         lint + testes bats (o mínimo antes de qualquer commit)
#   make ci           portão 1 completo, igual ao GitHub: test + actionlint + zizmor + gitleaks
#   make ferramentas  instala as ferramentas fixadas (ci/ferramentas.txt) em .ci-bin/
#   make hooks        ativa os hooks de ci/hooks (pre-commit e pre-push)
SHELL := /bin/bash
CI_BIN := $(CURDIR)/.ci-bin
export PATH := $(CI_BIN)/bin:$(PATH)
SCRIPTS := $(wildcard provision/*.sh) bin/jarvis bin/jarvis-expose bin/jarvis-peer bin/jarvis-backup \
           $(wildcard ci/*.sh) $(wildcard ci/hooks/*)

.PHONY: test lint unit ci ferramentas hooks
test: lint unit

lint:
	shellcheck -x $(SCRIPTS)
	@for f in $(SCRIPTS); do bash -n "$$f" || exit 1; done

unit:
	bats tests

ci: test
	@for t in actionlint zizmor gitleaks; do \
	  command -v $$t >/dev/null || { echo "faltando: $$t — rode: make ferramentas"; exit 1; }; done
	actionlint
	zizmor --offline .
	gitleaks git --redact --no-banner .

ferramentas:
	ci/instalar-ferramentas.sh $(CI_BIN) shellcheck bats actionlint zizmor gitleaks

hooks:
	git config core.hooksPath ci/hooks
	@echo "hooks ativos: ci/hooks/pre-commit e ci/hooks/pre-push"
```

E acrescentar ao `.gitignore`:

```
# Ferramentas do CI instaladas localmente (make ferramentas)
.ci-bin/
```

- [ ] **Passo 8: instalar de verdade e rodar os testes**

Rode: `make ferramentas && make test`
Esperado: as 5 ferramentas instaladas, com uma linha `ok …` cada (os checksums reais conferem), e todos os testes passando.

- [ ] **Passo 9: Commit**

```bash
git add ci/ferramentas.txt ci/instalar-ferramentas.sh tests/ferramentas.bats tests/helpers.bash Makefile .gitignore
git commit -m "ci: ferramentas fixadas por SHA-256 e alvos make ci/ferramentas/hooks"
```

---

### Tarefa 2: Preflight em `lib.sh`

**Arquivos:**
- Modificar: `provision/lib.sh`
- Criar: `tests/preflight.bats`

**Interfaces:**
- Produz:
  - `check_vars`: imprime um erro por linha; retorna 1 se houver algum.
  - `check_os`: retorna 0 se for Ubuntu 24.04. Lê `${OS_RELEASE:-/etc/os-release}`.
  - `preflight REQ...`, com os requisitos `os root sudo-admin admin-keys cmd:X ci-env:VAR iface:IF user:U`. Se houver problemas, imprime `ERRO preflight encontrou N problema(s) — nada foi alterado:`, depois uma linha `  - …` por problema, e sai com 1.
  - `apt_get` (já existe). `ZONEINFO_DIR` (padrão `/usr/share/zoneinfo`) pode ser sobrescrito.

- [ ] **Passo 1: escrever os testes que falham, `tests/preflight.bats`**

```bash
load helpers

setup() {
  make_sandbox
  source "$REPO_ROOT/provision/lib.sh"
  printf 'ID=ubuntu\nVERSION_ID="24.04"\n' > "$SANDBOX/os-ok"
  export OS_RELEASE="$SANDBOX/os-ok"
}

invalido() {   # invalido VAR VALOR TRECHO_ESPERADO
  printf -v "$1" '%s' "$2"
  run check_vars
  [ "$status" -ne 0 ] || { echo "aceitou $1=$2"; return 1; }
  [[ "$output" == *"$3"* ]] || { echo "mensagem sem '$3': $output"; return 1; }
}

@test "valores padrão do vars.sh passam" {
  run check_vars
  [ "$status" -eq 0 ]
}

@test "usuários: formato, iguais entre si ou root" {
  invalido ADMIN_USER "Renato" ADMIN_USER
  ADMIN_USER=renpv
  invalido HERMES_USER "" HERMES_USER
  HERMES_USER=renpv; run check_vars; [[ "$output" == *"diferentes"* ]]
  HERMES_USER=root; run check_vars; [[ "$output" == *"root"* ]]
}

@test "caminhos precisam ser absolutos, sem .. e sem espaço" {
  invalido HERMES_DIR "var/lib/hermes" HERMES_DIR
  HERMES_DIR=/var/lib/hermes
  invalido JARVIS_DIR "/opt/../etc" JARVIS_DIR
  JARVIS_DIR=/opt/jarvis
  invalido JARVIS_DIR "/opt/meu jarvis" JARVIS_DIR
}

@test "GitHub: slug dono/repo e URL do github" {
  invalido GITHUB_SLUG "renpv" GITHUB_SLUG
  GITHUB_SLUG=renpv/jarvis
  invalido GITHUB_REPO "git@gitlab.com:renpv/jarvis.git" GITHUB_REPO
}

@test "TIMEZONE precisa existir" {
  invalido TIMEZONE "America/Fortalesa" TIMEZONE
  TIMEZONE=America/Fortaleza
  invalido TIMEZONE "../../etc/passwd" TIMEZONE
}

@test "DOMAIN e WG_IF" {
  invalido DOMAIN "jarvis" DOMAIN
  DOMAIN=jarvis.lan
  invalido DOMAIN "Jarvis.LAN" DOMAIN
  DOMAIN=jarvis.lan
  invalido WG_IF "wg 0" WG_IF
}

@test "portas: limites 1..65535" {
  WG_PORT=65535; run check_vars; [ "$status" -eq 0 ]
  invalido WG_PORT 65536 WG_PORT
  WG_PORT=51820
  invalido WG_PORT 0 WG_PORT
  WG_PORT=51820
  invalido DASHBOARD_PORT "91a9" DASHBOARD_PORT
}

@test "faixa de apps e porta do dashboard" {
  APP_PORT_MIN=8199 APP_PORT_MAX=8100
  run check_vars; [[ "$output" == *"APP_PORT_MIN"* ]]
  APP_PORT_MIN=8100 APP_PORT_MAX=8199 DASHBOARD_PORT=8100
  run check_vars; [ "$status" -ne 0 ]; [[ "$output" == *"DASHBOARD_PORT"* ]]
  DASHBOARD_PORT=8200
  run check_vars; [ "$status" -eq 0 ]
}

@test "rede WireGuard" {
  invalido WG_NET "10.8" WG_NET
  WG_NET=10.8.0
  invalido WG_NET "10.8.300" WG_NET
  WG_NET=10.8.0
  invalido WG_SERVER_IP "10.9.0.1" WG_SERVER_IP
  WG_SERVER_IP=10.8.0.255; run check_vars; [ "$status" -eq 0 ]
  invalido WG_SERVER_IP "10.8.0.256" WG_SERVER_IP
}

@test "WG_ENDPOINT vazio, IPv4 ou nome DNS" {
  WG_ENDPOINT=""; run check_vars; [ "$status" -eq 0 ]
  WG_ENDPOINT=203.0.113.5; run check_vars; [ "$status" -eq 0 ]
  WG_ENDPOINT=vpn.exemplo.com; run check_vars; [ "$status" -eq 0 ]
  invalido WG_ENDPOINT "203.0.113" WG_ENDPOINT
}

@test "preflight lista todos os problemas de uma vez" {
  TIMEZONE=America/Fortalesa WG_PORT=99999
  run preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *"TIMEZONE"* ]]
  [[ "$output" == *"WG_PORT"* ]]
  [[ "$output" == *"2 problema"* ]]
}

@test "preflight para antes de qualquer efeito" {
  cat > "$SANDBOX/script.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$REPO_ROOT/provision/lib.sh"
preflight
touch "$SANDBOX/sentinela"
EOF
  chmod +x "$SANDBOX/script.sh"
  WG_PORT=99999 run "$SANDBOX/script.sh"
  [ "$status" -ne 0 ]
  [ ! -e "$SANDBOX/sentinela" ]
  run "$SANDBOX/script.sh"
  [ "$status" -eq 0 ]
  [ -e "$SANDBOX/sentinela" ]
}

@test "requisito os" {
  run preflight os; [ "$status" -eq 0 ]
  printf 'ID=debian\nVERSION_ID="12"\n' > "$SANDBOX/os-ruim"
  OS_RELEASE="$SANDBOX/os-ruim" run preflight os
  [ "$status" -ne 0 ]; [[ "$output" == *"Ubuntu 24.04"* ]]
}

@test "requisitos cmd, user, ci-env e desconhecido" {
  run preflight cmd:comando-que-nao-existe-xyz; [ "$status" -ne 0 ]
  run preflight "user:usuario-que-nao-existe-xyz"; [ "$status" -ne 0 ]
  run preflight "user:$(id -un)"; [ "$status" -eq 0 ]
  JARVIS_CI=1 run preflight ci-env:SENHA_TESTE_XYZ; [ "$status" -ne 0 ]
  run preflight ci-env:SENHA_TESTE_XYZ; [ "$status" -eq 0 ]
  run preflight requisito-inventado; [ "$status" -ne 0 ]
}

@test "requisito sudo-admin" {
  SUDO_USER=outro run preflight sudo-admin
  [ "$status" -ne 0 ]
  SUDO_USER=$ADMIN_USER run preflight sudo-admin
  [ "$status" -eq 0 ]
}
```

- [ ] **Passo 2: rodar e ver falhar**

Rode: `bats tests/preflight.bats`
Esperado: FAIL, porque `check_vars` e `preflight` não existem.

- [ ] **Passo 3: implementar.** Acrescentar ao fim de `provision/lib.sh`:

```bash
# ── Preflight: valida tudo ANTES de alterar a máquina ─────────────────────────

_is_port() { [[ $1 =~ ^[1-9][0-9]{0,4}$ ]] && (($1 <= 65535)); }
_is_octet() { [[ $1 =~ ^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$ ]]; }
_is_ipv4() {
  [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  local IFS=. o
  for o in $1; do _is_octet "$o" || return 1; done
}
_is_dns() { [[ $1 =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; }
_is_user() { [[ $1 =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
_is_abspath() { [[ $1 == /* && $1 != *..* && $1 != *[[:space:]]* ]]; }

# check_vars — valida o vars.sh. Imprime um problema por linha; retorna 1 se houver algum.
check_vars() {
  local e=() p
  _is_user "$ADMIN_USER" || e+=("ADMIN_USER inválido: '$ADMIN_USER' (minúsculas, números, _ e -)")
  _is_user "$HERMES_USER" || e+=("HERMES_USER inválido: '$HERMES_USER'")
  [[ $ADMIN_USER != "$HERMES_USER" ]] || e+=("ADMIN_USER e HERMES_USER precisam ser diferentes")
  [[ $ADMIN_USER != root && $HERMES_USER != root ]] || e+=("ADMIN_USER/HERMES_USER não podem ser root")
  _is_abspath "$HERMES_DIR" || e+=("HERMES_DIR precisa ser caminho absoluto, sem '..' e sem espaço: '$HERMES_DIR'")
  _is_abspath "$JARVIS_DIR" || e+=("JARVIS_DIR precisa ser caminho absoluto, sem '..' e sem espaço: '$JARVIS_DIR'")
  [[ $GITHUB_SLUG =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || e+=("GITHUB_SLUG precisa ser dono/repo: '$GITHUB_SLUG'")
  [[ $GITHUB_REPO == git@github.com:* || $GITHUB_REPO == https://github.com/* ]] ||
    e+=("GITHUB_REPO precisa ser do github.com: '$GITHUB_REPO'")
  [[ -n $TIMEZONE && $TIMEZONE != *..* && -f ${ZONEINFO_DIR:-/usr/share/zoneinfo}/$TIMEZONE ]] ||
    e+=("TIMEZONE inexistente: '$TIMEZONE' (veja timedatectl list-timezones)")
  _is_dns "$DOMAIN" || e+=("DOMAIN inválido: '$DOMAIN' (minúsculas, com pelo menos um ponto)")
  [[ $WG_IF =~ ^[a-z][a-z0-9]{0,14}$ ]] || e+=("WG_IF inválido: '$WG_IF'")
  for p in WG_PORT DASHBOARD_PORT APP_PORT_MIN APP_PORT_MAX; do
    _is_port "${!p}" || e+=("$p inválida: '${!p}' (inteiro de 1 a 65535)")
  done
  if _is_port "$APP_PORT_MIN" && _is_port "$APP_PORT_MAX"; then
    ((APP_PORT_MIN < APP_PORT_MAX)) || e+=("APP_PORT_MIN ($APP_PORT_MIN) precisa ser menor que APP_PORT_MAX ($APP_PORT_MAX)")
    if _is_port "$DASHBOARD_PORT" && ((DASHBOARD_PORT >= APP_PORT_MIN && DASHBOARD_PORT <= APP_PORT_MAX)); then
      e+=("DASHBOARD_PORT ($DASHBOARD_PORT) não pode cair na faixa de apps $APP_PORT_MIN–$APP_PORT_MAX")
    fi
  fi
  _is_ipv4 "$WG_NET.0" || e+=("WG_NET inválida: '$WG_NET' (três octetos, ex.: 10.8.0)")
  if _is_ipv4 "$WG_SERVER_IP"; then
    [[ ${WG_SERVER_IP%.*} == "$WG_NET" ]] || e+=("WG_SERVER_IP ($WG_SERVER_IP) fora da rede $WG_NET.0/24")
  else
    e+=("WG_SERVER_IP inválido: '$WG_SERVER_IP'")
  fi
  if [[ -n $WG_ENDPOINT ]] && ! _is_ipv4 "$WG_ENDPOINT" && ! _is_dns "$WG_ENDPOINT"; then
    e+=("WG_ENDPOINT inválido: '$WG_ENDPOINT' (vazio, IPv4 ou nome DNS)")
  fi
  ((${#e[@]} == 0)) && return 0
  printf '%s\n' "${e[@]}"
  return 1
}

# check_os — Ubuntu 24.04?
check_os() {
  local f=${OS_RELEASE:-/etc/os-release}
  [[ -r $f ]] || return 1
  # shellcheck disable=SC1090  # arquivo do sistema (ou de teste)
  (. "$f" && [[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 24.04 ]])
}

# preflight [REQUISITO...] — valida variáveis e requisitos; se houver problema, lista TODOS e sai.
preflight() {
  local errs=() out r v h
  if ! out=$(check_vars); then mapfile -t errs <<<"$out"; fi
  for r in "$@"; do
    case $r in
      os) check_os || errs+=("sistema: este script precisa de Ubuntu 24.04") ;;
      root) [[ $EUID -eq 0 ]] || errs+=("rode com sudo: sudo $0") ;;
      sudo-admin) [[ ${SUDO_USER:-} == "$ADMIN_USER" ]] || errs+=("rode como $ADMIN_USER usando sudo (não como root direto)") ;;
      admin-keys)
        h=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
        [[ -n $h && -s $h/.ssh/authorized_keys ]] ||
          errs+=("$ADMIN_USER sem authorized_keys: endurecer o SSH agora trancaria você para fora")
        ;;
      cmd:*) command -v "${r#cmd:}" >/dev/null || errs+=("comando ausente: ${r#cmd:}") ;;
      ci-env:*)
        v=${r#ci-env:}
        if [[ ${JARVIS_CI:-} == 1 && -z ${!v:-} ]]; then errs+=("modo CI: defina $v"); fi
        ;;
      iface:*)
        ip -4 addr show "${r#iface:}" 2>/dev/null | grep -q "inet $WG_SERVER_IP/" ||
          errs+=("interface ${r#iface:} sem o IP $WG_SERVER_IP (rode 20-wireguard.sh antes)")
        ;;
      user:*) id "${r#user:}" &>/dev/null || errs+=("usuário inexistente: ${r#user:}") ;;
      *) errs+=("requisito desconhecido no preflight: $r") ;;
    esac
  done
  ((${#errs[@]} == 0)) && return 0
  printf '%sERRO%s preflight encontrou %d problema(s) — nada foi alterado:\n' "$C_R" "$C_0" "${#errs[@]}" >&2
  printf '  - %s\n' "${errs[@]}" >&2
  exit 1
}
```

- [ ] **Passo 4: rodar e ver passar**

Rode: `bats tests/preflight.bats && shellcheck -x provision/lib.sh`
Esperado: todos passam e o lint fica limpo.

- [ ] **Passo 5: Commit**

```bash
git add provision/lib.sh tests/preflight.bats
git commit -m "feat: preflight valida vars.sh e requisitos antes de qualquer alteração"
```

---

### Tarefa 3: Preflight e modo CI nos scripts de provisionamento

**Arquivos:**
- Modificar: `provision/00-bootstrap.sh`, `10-sistema.sh`, `20-wireguard.sh`, `30-dns-caddy.sh`, `40-hermes.sh`, `50-docker-rootless.sh`, `60-backup.sh`
- Criar: `tests/provision.bats`

**Interfaces:**
- Consome `preflight` (Tarefa 2).
- **Modo CI** (`JARVIS_CI=1`):
  - `00`: pula o `full-upgrade`, a senha, a deploy key e o clone. Se o root não tiver `authorized_keys`, cria uma chave descartável.
  - `30`: a senha do dashboard vem de `JARVIS_DASHBOARD_PASSWORD`.
- O `00` instala `openssh-server` e `jq` (o runner não tem sshd; o `jarvis deploy` usa jq) e clona com `-b prod`.
- O `50` instala o rootless em cima de um Docker já existente e cria o perfil AppArmor do rootlesskit se não existir.

- [ ] **Passo 1: escrever o teste que falha, `tests/provision.bats`**

```bash
load helpers

@test "todo script de provisionamento chama preflight antes de qualquer alteração" {
  for f in "$REPO_ROOT"/provision/[0-9]*.sh; do
    primeira=$(grep -nE '^(preflight|apt_get|apt_install|install |useradd|usermod|systemctl|ufw|timedatectl|mkdir|chmod|ln )' "$f" | head -1)
    [[ $primeira == *preflight* ]] || { echo "$(basename "$f"): primeira ação não é preflight: $primeira"; return 1; }
  done
}

@test "requisitos de preflight de cada script batem com a spec" {
  grep -qx 'preflight os root' "$REPO_ROOT/provision/00-bootstrap.sh"
  grep -qx 'preflight os root sudo-admin admin-keys' "$REPO_ROOT/provision/10-sistema.sh"
  grep -qx 'preflight os root' "$REPO_ROOT/provision/20-wireguard.sh"
  grep -qx 'preflight os root "iface:$WG_IF" ci-env:JARVIS_DASHBOARD_PASSWORD' "$REPO_ROOT/provision/30-dns-caddy.sh"
  grep -qx 'preflight os root' "$REPO_ROOT/provision/40-hermes.sh"
  grep -qx 'preflight os root "user:$HERMES_USER"' "$REPO_ROOT/provision/50-docker-rootless.sh"
  grep -qx 'preflight os root "user:$HERMES_USER"' "$REPO_ROOT/provision/60-backup.sh"
}

@test "bootstrap clona o branch prod" {
  grep -q 'git clone -b prod' "$REPO_ROOT/provision/00-bootstrap.sh"
}

@test "nenhum script usa require_root solto (o preflight cobre)" {
  run grep -l '^require_root' "$REPO_ROOT"/provision/[0-9]*.sh
  [ -z "$output" ]
}
```

- [ ] **Passo 2: rodar e ver falhar**

Rode: `bats tests/provision.bats`
Esperado: FAIL nos 4 testes.

- [ ] **Passo 3: editar os scripts**

Em **cada** um dos 7 scripts, troque a linha `require_root` pela linha de preflight correspondente:

| Script | Linha nova (exata) |
|---|---|
| `00-bootstrap.sh` | `preflight os root` |
| `10-sistema.sh` | `preflight os root sudo-admin admin-keys` |
| `20-wireguard.sh` | `preflight os root` |
| `30-dns-caddy.sh` | `preflight os root "iface:$WG_IF" ci-env:JARVIS_DASHBOARD_PASSWORD` |
| `40-hermes.sh` | `preflight os root` |
| `50-docker-rootless.sh` | `preflight os root "user:$HERMES_USER"` |
| `60-backup.sh` | `preflight os root "user:$HERMES_USER"` |

Depois, em cada script, remova as verificações que o preflight passou a cobrir:
- `10-sistema.sh`: as duas linhas `[[ ${SUDO_USER:-} == ... ]] || die ...` e `[[ -s $home/.ssh/authorized_keys ]] || die ...` (mantenha o `home=$(getent …)` só se ainda for usado; não é, então remova também).
- `30-dns-caddy.sh`: a linha `ip -4 addr show "$WG_IF" ... || die "rode 20-wireguard.sh antes"`.
- `50-docker-rootless.sh`: a linha `id "$HERMES_USER" &>/dev/null || die "rode 40-hermes.sh antes"`.

**Em `00-bootstrap.sh`**, substitua o bloco que vai de `log "atualizando o sistema` até `usermod -aG sudo "$ADMIN_USER"` (inclusive) por:

```bash
log "atualizando o sistema (pode demorar alguns minutos)"
apt_get update -q
if [[ ${JARVIS_CI:-} != 1 ]]; then apt_get -y -q full-upgrade; fi
# openssh-server: já vem na VPS, mas não no runner do CI. jq: usado pelo jarvis deploy.
apt_install git curl ca-certificates jq openssh-server

if id "$ADMIN_USER" &>/dev/null; then
  ok "usuário $ADMIN_USER já existe"
else
  log "criando usuário $ADMIN_USER"
  adduser --disabled-password --gecos "" "$ADMIN_USER"
fi
usermod -aG sudo "$ADMIN_USER"
```

Substitua o bloco da senha (`if [[ $(passwd -S ...` … `fi`) por:

```bash
if [[ ${JARVIS_CI:-} != 1 && $(passwd -S "$ADMIN_USER" | awk '{print $2}') != P ]]; then
  log "defina a senha de $ADMIN_USER (usada pelo sudo; o login SSH continua só por chave)"
  passwd "$ADMIN_USER"
fi
```

Logo antes da linha `[[ -s /root/.ssh/authorized_keys ]] || die ...`, insira:

```bash
if [[ ${JARVIS_CI:-} == 1 && ! -s /root/.ssh/authorized_keys ]]; then
  # CI: VM descartável sem chave de root. Uma chave descartável satisfaz a checagem do 10-sistema.
  install -d -m 700 /root/.ssh
  ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/ci_descartavel
  cat /root/.ssh/ci_descartavel.pub >>/root/.ssh/authorized_keys
fi
```

Substitua o bloco da chave do GitHub e do clone (de `key="$home/.ssh/id_ed25519_github"` até o `fi` do `if [[ ! -d $JARVIS_DIR/.git ]]`) por:

```bash
key="$home/.ssh/id_ed25519_github"
if [[ ${JARVIS_CI:-} != 1 && ! -f $key ]]; then
  runuser -u "$ADMIN_USER" -- ssh-keygen -q -t ed25519 -N "" -C "$ADMIN_USER@$(hostname)-jarvis" -f "$key"
fi

if [[ ! -d $JARVIS_DIR/.git ]]; then
  [[ ${JARVIS_CI:-} != 1 ]] || die "modo CI: o repo precisa já estar em $JARVIS_DIR"
  echo
  echo "Adicione esta chave como Deploy Key, marcando 'Allow write access', em:"
  echo "  https://github.com/$GITHUB_SLUG/settings/keys/new"
  echo
  cat "$key.pub"
  echo
  read -rp "Pressione Enter depois de salvar a chave no GitHub... "
  install -d -m 750 -o "$ADMIN_USER" -g "$ADMIN_USER" "$JARVIS_DIR"
  runuser -u "$ADMIN_USER" -- env \
    GIT_SSH_COMMAND="ssh -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
    git clone -b prod "$GITHUB_REPO" "$JARVIS_DIR"
  runuser -u "$ADMIN_USER" -- git -C "$JARVIS_DIR" config core.sshCommand "ssh -i $key -o IdentitiesOnly=yes"
fi
```

**Em `30-dns-caddy.sh`**, substitua o bloco `if [[ ! -f /etc/caddy/secrets.env ]]; then … fi` por:

```bash
if [[ ! -f /etc/caddy/secrets.env ]]; then
  if [[ ${JARVIS_CI:-} == 1 ]]; then
    hash=$(caddy hash-password --plaintext "$JARVIS_DASHBOARD_PASSWORD")
  else
    log "crie a senha do dashboard (usuário: $ADMIN_USER). Ela não aparece na tela."
    hash=$(caddy hash-password)
  fi
  [[ $hash == \$2* ]] || die "não consegui gerar o hash da senha"
  (umask 077 && printf "DASHBOARD_USER='%s'\nDASHBOARD_HASH='%s'\n" "$ADMIN_USER" "$hash" >/etc/caddy/secrets.env)
fi
```

**Em `50-docker-rootless.sh`**, substitua o bloco que vai de `log "Docker (repositório oficial)"` até a linha `systemctl disable --now docker.service ...` (inclusive) por:

```bash
log "Docker (repositório oficial)"
# Se o repositório do Docker já estiver configurado (ex.: runner do CI), só completa os pacotes.
if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091  # arquivo do sistema
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
    >/etc/apt/sources.list.d/docker.list
  apt_get update -q
fi
apt_install docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras docker-compose-plugin uidmap

# Ubuntu 24.04 restringe user namespaces sem privilégio; o rootlesskit precisa de um perfil AppArmor.
if [[ -d /etc/apparmor.d ]] && ! grep -rqs rootlesskit /etc/apparmor.d; then
  cat >/etc/apparmor.d/usr.bin.rootlesskit <<'EOF'
abi <abi/4.0>,
include <tunables/global>

"/usr/bin/rootlesskit" flags=(unconfined) {
  userns,

  include if exists <local/usr.bin.rootlesskit>
}
EOF
  apparmor_parser -r /etc/apparmor.d/usr.bin.rootlesskit
fi

# Sem o Docker de root: só o rootless do hermes.
systemctl disable --now docker.service docker.socket containerd.service 2>/dev/null || true
```

- [ ] **Passo 4: rodar e ver passar**

Rode: `bats tests/provision.bats && make lint`
Esperado: 4/4 passam e o lint fica limpo.

- [ ] **Passo 5: Commit**

```bash
git add provision tests/provision.bats
git commit -m "feat: preflight em todos os scripts, modo CI no 00/30 e Docker rootless robusto no 50"
```

---

### Tarefa 4: `jarvis check` e preflight em apply/import/diff

**Arquivos:**
- Modificar: `bin/jarvis`
- Criar: `tests/check.bats`
- Modificar: `tests/jarvis.bats` (um teste novo)

**Interfaces:**
- `jarvis check`: mostra `✅`/`❌` para cada item: variáveis do `vars.sh`, Ubuntu 24.04, comandos `git curl jq sudo`, `.env` completo e token de deploy (`$DEPLOY_TOKEN_FILE` legível, modo 600). Sai com 0 só se tudo passar.
- `DEPLOY_TOKEN_FILE` (padrão `$HOME/.config/jarvis/github-token`).
- `apply`, `import` e `diff` chamam `preflight "user:$HERMES_USER"` antes de tudo.

- [ ] **Passo 1: escrever os testes que falham.** Criar `tests/check.bats`:

```bash
load helpers

setup() {
  make_sandbox
  export JARVIS_REPO="$REPO_ROOT"
  export HERMES_HOME="$SANDBOX/live/.hermes" HERMES_USER="$(id -un)" SUDO="" HSUDO=""
  mkdir -p "$HERMES_HOME"
  printf '%s=x\n' OPENAI_API_KEY TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USERS TELEGRAM_HOME_CHANNEL GITHUB_TOKEN > "$HERMES_HOME/.env"
  chmod 600 "$HERMES_HOME/.env"
  printf 'ID=ubuntu\nVERSION_ID="24.04"\n' > "$SANDBOX/os"
  echo token-falso > "$SANDBOX/token" && chmod 600 "$SANDBOX/token"
  export OS_RELEASE="$SANDBOX/os" DEPLOY_TOKEN_FILE="$SANDBOX/token"
}

@test "check com tudo certo mostra só ✅ e sai com 0" {
  run "$REPO_ROOT/bin/jarvis" check
  [ "$status" -eq 0 ]
  [[ "$output" != *"❌"* ]]
}

@test "check sem token mostra ❌ no token e sai com 1" {
  rm "$SANDBOX/token"
  run "$REPO_ROOT/bin/jarvis" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"❌"*"token"* ]]
}

@test "check com token de permissão aberta reprova" {
  chmod 644 "$SANDBOX/token"
  run "$REPO_ROOT/bin/jarvis" check
  [ "$status" -eq 1 ]
}

@test "check mostra os problemas do vars.sh e não altera nada" {
  WG_PORT=99999 run "$REPO_ROOT/bin/jarvis" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"WG_PORT"* ]]
}
```

E acrescentar ao fim de `tests/jarvis.bats`:

```bash
@test "apply/import/diff param no preflight com vars.sh inválido" {
  for c in apply import diff; do
    WG_PORT=99999 run "$JARVIS" $c
    [ "$status" -ne 0 ] || { echo "$c passou"; return 1; }
    [[ "$output" == *"WG_PORT"* ]]
  done
  [ ! -e "$HERMES_HOME/config.yaml" ]
}
```

- [ ] **Passo 2: rodar e ver falhar**

Rode: `bats tests/check.bats tests/jarvis.bats`
Esperado: FAIL nos testes novos.

- [ ] **Passo 3: implementar em `bin/jarvis`**

3a. No cabeçalho de ajuda (comentários do topo), depois da linha `#   jarvis check-env …`, acrescente:

```bash
#   jarvis check             valida vars.sh, sistema, comandos, .env e token (não altera nada)
#   jarvis deploy            traz o prod do GitHub SÓ se todos os testes passaram (veja docs)
```

E troque `sed -n '2,12p'` por `sed -n '2,14p'` no bloco de ajuda do `case`.

3b. Depois da linha `VPS_SSH=…`, acrescente:

```bash
DEPLOY_TOKEN_FILE=${DEPLOY_TOKEN_FILE:-$HOME/.config/jarvis/github-token}
```

3c. Na primeira linha de `cmd_diff`, `cmd_apply` e `cmd_import`, insira:

```bash
  preflight "user:$HERMES_USER"
```

3d. Antes de `cmd_status()`, acrescente:

```bash
CHECK_FAIL=0
_item() {   # _item 0|1 TEXTO
  if [[ $1 == 0 ]]; then printf '  ✅ %s\n' "$2"; else printf '  ❌ %s\n' "$2"; CHECK_FAIL=1; fi
}

token_ok() {
  [[ -r $DEPLOY_TOKEN_FILE && -s $DEPLOY_TOKEN_FILE && $(stat -c %a "$DEPLOY_TOKEN_FILE") == 600 ]]
}

cmd_check() {
  local out c falta=()
  log "verificação (nada é alterado)"
  if out=$(check_vars); then
    _item 0 "variáveis do vars.sh"
  else
    _item 1 "variáveis do vars.sh:"
    sed 's/^/       - /' <<<"$out"
  fi
  if check_os; then _item 0 "Ubuntu 24.04"; else _item 1 "sistema não é Ubuntu 24.04"; fi
  for c in git curl jq sudo; do command -v "$c" >/dev/null || falta+=("$c"); done
  if ((${#falta[@]} == 0)); then _item 0 "comandos: git curl jq sudo"; else _item 1 "comandos ausentes: ${falta[*]}"; fi
  if (cmd_check_env) >/dev/null 2>&1; then _item 0 ".env do Hermes completo"; else _item 1 ".env do Hermes (detalhes: jarvis check-env)"; fi
  if token_ok; then
    _item 0 "token de deploy ($DEPLOY_TOKEN_FILE)"
  else
    _item 1 "token de deploy ausente ou sem modo 600: $DEPLOY_TOKEN_FILE (docs/aprendizado/80-ci-e-fluxo-git.md)"
  fi
  return "$CHECK_FAIL"
}
```

3e. No `case` final, acrescente antes de `status)`:

```bash
  check) cmd_check ;;
```

- [ ] **Passo 4: rodar e ver passar**

Rode: `bats tests/check.bats tests/jarvis.bats && shellcheck -x bin/jarvis`
Esperado: todos passam e o lint fica limpo.

- [ ] **Passo 5: Commit**

```bash
git add bin/jarvis tests/check.bats tests/jarvis.bats
git commit -m "feat: jarvis check e preflight em apply/import/diff"
```

---

### Tarefa 5: `jarvis deploy`

**Arquivos:**
- Modificar: `bin/jarvis`
- Criar: `tests/deploy.bats`

**Interfaces:**
- Ambiente aceito:
  - `GITHUB_API` (padrão `https://api.github.com`);
  - `JARVIS_HTTP`: comando que recebe a URL e imprime JSON (testes). Vazio = curl com o token;
  - `DEPLOY_BRANCH` (padrão `prod`);
  - `DEPLOY_TOKEN_FILE`.
- Lê a resposta de confirmação na entrada padrão (`s` confirma).
- Saída 0 quando atualiza, não há nada novo ou o usuário cancela (com "cancelado"). Saída 1 nos erros.

- [ ] **Passo 1: escrever os testes que falham, `tests/deploy.bats`**

```bash
load helpers

setup() {
  make_sandbox
  ORIGIN="$SANDBOX/origin.git"
  WORK="$SANDBOX/work"
  git init -q --bare -b main "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK" 2>/dev/null
  mkdir -p "$WORK/ci" "$WORK/hermes" "$WORK/bin"
  cp -r "$REPO_ROOT/provision" "$WORK/"
  printf 'portao-1 / lint\nintegracao\n' > "$WORK/ci/testes-exigidos.txt"
  echo v1 > "$WORK/hermes/SOUL.md"
  echo v1 > "$WORK/bin/jarvis-expose"
  git -C "$WORK" add -A && git -C "$WORK" commit -qm inicial
  git -C "$WORK" push -q origin HEAD:main HEAD:prod
  export JARVIS_REPO="$SANDBOX/vps"
  git clone -q -b prod "$ORIGIN" "$JARVIS_REPO"
  echo token-falso > "$SANDBOX/token" && chmod 600 "$SANDBOX/token"
  cat > "$SANDBOX/api" <<EOF
#!/usr/bin/env bash
echo "\$1" >> "$SANDBOX/api.log"
cat "$SANDBOX/checks.json"
EOF
  chmod +x "$SANDBOX/api"
  export DEPLOY_TOKEN_FILE="$SANDBOX/token" JARVIS_HTTP="$SANDBOX/api"
  export HERMES_USER="$(id -un)" SUDO="" HSUDO="" SYSTEMCTL=":"
  JARVIS="$REPO_ROOT/bin/jarvis"
}

novo_commit() {   # novo_commit ARQUIVO [MENSAGEM]
  mkdir -p "$(dirname "$WORK/$1")"
  echo "# $RANDOM" >> "$WORK/$1"   # comentário: não quebra arquivos como provision/vars.sh
  git -C "$WORK" add -A && git -C "$WORK" commit -qm "${2:-muda $1}"
  git -C "$WORK" push -q origin HEAD:main HEAD:prod
}

checks() {   # checks "nome|status|conclusao|started_at" ...
  local runs=() c n s co t
  for c in "$@"; do
    IFS='|' read -r n s co t <<<"$c"
    runs+=("{\"name\":\"$n\",\"status\":\"$s\",\"conclusion\":\"$co\",\"started_at\":\"${t:-2026-10-19T10:00:00Z}\"}")
  done
  local IFS=,
  printf '{"total_count":%d,"check_runs":[%s]}\n' "${#runs[@]}" "${runs[*]}" > "$SANDBOX/checks.json"
}

verdes() { checks "portao-1 / lint|completed|success" "integracao|completed|success"; }

@test "nada novo no prod: sai com 0 sem consultar a API" {
  verdes
  run "$JARVIS" deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"nada novo"* ]]
  [ ! -e "$SANDBOX/api.log" ]
}

@test "commit novo com testes verdes: avança e consulta o commit certo" {
  novo_commit docs/x.md "docs: algo"
  verdes
  sha=$(git -C "$WORK" rev-parse HEAD)
  run bash -c "printf 's\n' | '$JARVIS' deploy"
  [ "$status" -eq 0 ]
  [ "$(git -C "$JARVIS_REPO" rev-parse HEAD)" = "$sha" ]
  grep -q "/commits/$sha/check-runs" "$SANDBOX/api.log"
  [[ "$output" == *"docs: algo"* ]]
}

@test "teste vermelho: recusa, lista o teste e não mexe no HEAD" {
  antes=$(git -C "$JARVIS_REPO" rev-parse HEAD)
  novo_commit docs/x.md
  checks "portao-1 / lint|completed|success" "integracao|completed|failure"
  run bash -c "printf 's\n' | '$JARVIS' deploy"
  [ "$status" -ne 0 ]
  [[ "$output" == *"integracao"* ]]
  [ "$(git -C "$JARVIS_REPO" rev-parse HEAD)" = "$antes" ]
}

@test "teste ausente ou ainda rodando: recusa" {
  novo_commit docs/x.md
  checks "portao-1 / lint|in_progress|"
  run bash -c "printf 's\n' | '$JARVIS' deploy"
  [ "$status" -ne 0 ]
  [[ "$output" == *"portao-1 / lint"* ]]
  [[ "$output" == *"integracao"*"ausente"* ]]
}

@test "re-run: vale o check mais recente" {
  novo_commit docs/x.md
  checks "portao-1 / lint|completed|success" \
         "integracao|completed|failure|2026-10-19T10:00:00Z" \
         "integracao|completed|success|2026-10-19T11:00:00Z"
  run bash -c "printf 's\n' | '$JARVIS' deploy"
  [ "$status" -eq 0 ]
  checks "portao-1 / lint|completed|success" \
         "integracao|completed|success|2026-10-19T10:00:00Z" \
         "integracao|completed|failure|2026-10-19T11:00:00Z"
  novo_commit docs/y.md
  run bash -c "printf 's\n' | '$JARVIS' deploy"
  [ "$status" -ne 0 ]
}

@test "lista de testes exigidos vem do HEAD local, não do commit que chega" {
  printf 'portao-1 / lint\n' > "$WORK/ci/testes-exigidos.txt"
  novo_commit docs/x.md "ci: afrouxa exigências"
  checks "portao-1 / lint|completed|success"
  run bash -c "printf 's\n' | '$JARVIS' deploy"
  [ "$status" -ne 0 ]
  [[ "$output" == *"integracao"* ]]
}

@test "resposta diferente de s cancela sem mexer no HEAD" {
  antes=$(git -C "$JARVIS_REPO" rev-parse HEAD)
  novo_commit docs/x.md
  verdes
  run bash -c "printf 'n\n' | '$JARVIS' deploy"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cancelado"* ]]
  [ "$(git -C "$JARVIS_REPO" rev-parse HEAD)" = "$antes" ]
}

@test "sugere o script certo para cada caminho alterado" {
  echo v2 > "$WORK/bin/jarvis-expose"
  novo_commit system/caddy/Caddyfile.tpl
  verdes
  run bash -c "printf 's\n' | '$JARVIS' deploy"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sudo provision/50-docker-rootless.sh"* ]]
  [[ "$output" == *"sudo provision/30-dns-caddy.sh"* ]]
  [[ "$output" != *"sudo provision/20-wireguard.sh"* ]]
}

@test "mudança em vars.sh sugere todos os scripts, em ordem" {
  novo_commit provision/vars.sh
  verdes
  run bash -c "printf 's\n' | '$JARVIS' deploy"
  for s in 10-sistema 20-wireguard 30-dns-caddy 40-hermes 50-docker-rootless 60-backup; do
    [[ "$output" == *"sudo provision/$s.sh"* ]] || { echo "faltou $s"; return 1; }
  done
}

@test "mudança em hermes/ oferece o jarvis apply" {
  novo_commit hermes/SOUL.md
  verdes
  run bash -c "printf 's\nn\n' | '$JARVIS' deploy"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jarvis apply"* ]]
}

@test "histórico do prod reescrito: recusa" {
  antes=$(git -C "$JARVIS_REPO" rev-parse HEAD)
  git -C "$WORK" commit -q --amend -m "reescrito"
  git -C "$WORK" push -q -f origin HEAD:prod
  verdes
  run bash -c "printf 's\n' | '$JARVIS' deploy"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reescrito"* ]]
  [ "$(git -C "$JARVIS_REPO" rev-parse HEAD)" = "$antes" ]
}

@test "fora do branch prod ou com mudanças locais: recusa" {
  novo_commit docs/x.md
  verdes
  git -C "$JARVIS_REPO" switch -q -c feat/teste
  run "$JARVIS" deploy
  [ "$status" -ne 0 ]; [[ "$output" == *"prod"* ]]
  git -C "$JARVIS_REPO" switch -q prod
  echo sujo >> "$JARVIS_REPO/hermes/SOUL.md"
  run "$JARVIS" deploy
  [ "$status" -ne 0 ]; [[ "$output" == *"mudanças locais"* ]]
}

@test "sem token: recusa com instrução" {
  rm "$SANDBOX/token"
  novo_commit docs/x.md
  run "$JARVIS" deploy
  [ "$status" -ne 0 ]
  [[ "$output" == *"token"* ]]
}
```

- [ ] **Passo 2: rodar e ver falhar**

Rode: `bats tests/deploy.bats`
Esperado: FAIL (a ajuda sai com 2 para o subcomando desconhecido).

- [ ] **Passo 3: implementar em `bin/jarvis`.** Depois de `DEPLOY_TOKEN_FILE=…`, acrescente:

```bash
GITHUB_API=${GITHUB_API:-https://api.github.com}
DEPLOY_BRANCH=${DEPLOY_BRANCH:-prod}
JARVIS_HTTP=${JARVIS_HTTP:-}
```

Antes de `cmd_status()`, acrescente:

```bash
# api_get URL — GET autenticado na API do GitHub. O token vai por um descritor de arquivo
# (-H @…), nunca na linha de comando, onde outros usuários poderiam vê-lo com `ps`.
api_get() {
  if [[ -n $JARVIS_HTTP ]]; then
    $JARVIS_HTTP "$1"
    return
  fi
  curl -fsSL --max-time 30 \
    -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
    -H @<(printf 'Authorization: Bearer %s\n' "$(<"$DEPLOY_TOKEN_FILE")") "$1"
}

# sugestoes ARQUIVOS — o que rodar depois do deploy, conforme o que mudou (spec, seção 5).
sugestoes() {
  local f s todos=0
  declare -A quer=()
  while read -r f; do
    case $f in
      hermes/*) quer[apply]=1 ;;
      provision/lib.sh | provision/vars.sh) todos=1 ;;
      provision/10-* | system/apt/* | system/fail2ban/* | system/ssh/*) quer[10-sistema]=1 ;;
      provision/20-* | system/wireguard/* | bin/jarvis-peer) quer[20-wireguard]=1 ;;
      provision/30-* | system/dnsmasq/* | system/caddy/* | system/systemd/caddy-* | system/systemd/dnsmasq-*) quer[30-dns-caddy]=1 ;;
      provision/40-* | system/systemd/hermes-*) quer[40-hermes]=1 ;;
      provision/50-* | system/sudoers/* | bin/jarvis-expose) quer[50-docker-rootless]=1 ;;
      provision/60-* | system/systemd/jarvis-backup* | bin/jarvis-backup) quer[60-backup]=1 ;;
    esac
  done <<<"$1"
  for s in 10-sistema 20-wireguard 30-dns-caddy 40-hermes 50-docker-rootless 60-backup; do
    if ((todos)) || [[ -n ${quer[$s]:-} ]]; then echo "  sudo provision/$s.sh"; fi
  done
  if [[ -n ${quer[apply]:-} ]]; then echo "  jarvis apply"; fi
}

cmd_deploy() {
  local repo=$JARVIS_REPO head sha json name st reply mudou falhas=() exigidos
  token_ok || die "token de deploy ausente ou sem modo 600: $DEPLOY_TOKEN_FILE — crie conforme docs/aprendizado/80-ci-e-fluxo-git.md"
  [[ $(git -C "$repo" symbolic-ref --short -q HEAD) == "$DEPLOY_BRANCH" ]] ||
    die "$repo não está no branch $DEPLOY_BRANCH (git -C $repo switch $DEPLOY_BRANCH)"
  if ! git -C "$repo" diff --quiet || ! git -C "$repo" diff --cached --quiet; then
    die "há mudanças locais em $repo — se vieram de 'jarvis import', leve-as por um branch feat/* e PR (docs/operacao.md)"
  fi

  git -C "$repo" fetch -q origin "$DEPLOY_BRANCH"
  head=$(git -C "$repo" rev-parse HEAD)
  sha=$(git -C "$repo" rev-parse "origin/$DEPLOY_BRANCH")
  if [[ $sha == "$head" ]]; then
    ok "nada novo em $DEPLOY_BRANCH (${head:0:7})"
    return 0
  fi
  git -C "$repo" merge-base --is-ancestor "$head" "$sha" ||
    die "histórico do $DEPLOY_BRANCH foi reescrito (${head:0:7} não é ancestral de ${sha:0:7}); investigue antes de continuar"

  exigidos=$(git -C "$repo" show "HEAD:ci/testes-exigidos.txt" 2>/dev/null | grep -vE '^[[:space:]]*(#|$)' || true)
  [[ -n $exigidos ]] || die "ci/testes-exigidos.txt ausente ou vazio no HEAD local — deploy recusado"

  json=$(api_get "$GITHUB_API/repos/$GITHUB_SLUG/commits/$sha/check-runs?per_page=100") ||
    die "não consegui consultar os testes no GitHub (token válido? rede?)"
  while IFS= read -r name; do
    st=$(jq -r --arg n "$name" \
      '[.check_runs[] | select(.name == $n)] | sort_by(.started_at) | last
       | if . == null then "ausente" else "\(.status)/\(.conclusion // "-")" end' <<<"$json")
    [[ $st == completed/success ]] || falhas+=("$name: $st")
  done <<<"$exigidos"
  if ((${#falhas[@]})); then
    printf '  - %s\n' "${falhas[@]}" >&2
    die "testes não aprovados no commit ${sha:0:7} — deploy recusado"
  fi
  ok "todos os testes exigidos passaram em ${sha:0:7}"

  log "commits que vão entrar"
  git -C "$repo" log --oneline "$head..$sha"
  git -C "$repo" diff --stat "$head" "$sha"
  read -r -p "Aplicar na VPS? [s/N] " reply || reply=""
  if [[ $reply != s ]]; then
    ok "cancelado; nada mudou"
    return 0
  fi

  mudou=$(git -C "$repo" diff --name-only "$head" "$sha")
  git -C "$repo" merge -q --ff-only "$sha"
  ok "/opt/jarvis em ${sha:0:7}"

  log "próximos passos (você decide; scripts de root não rodam sozinhos)"
  sugestoes "$mudou"
  if grep -q '^hermes/' <<<"$mudou"; then
    read -r -p "Rodar 'jarvis apply' agora? [s/N] " reply || reply=""
    if [[ $reply == s ]]; then cmd_apply; fi
  fi
}
```

No `case` final, acrescente antes de `status)`:

```bash
  deploy) cmd_deploy ;;
```

- [ ] **Passo 4: rodar e ver passar**

Rode: `bats tests/deploy.bats && shellcheck -x bin/jarvis && make test`
Esperado: os 13 testes passam, o lint fica limpo e a suíte inteira está verde.

- [ ] **Passo 5: Commit**

```bash
git add bin/jarvis tests/deploy.bats
git commit -m "feat: jarvis deploy só traz o prod com todos os testes exigidos verdes"
```

---

### Tarefa 6: `ci/origem.sh`

**Arquivos:**
- Criar: `ci/origem.sh`, `tests/origem.bats`

**Interfaces:**
- Ambiente aceito:
  - `EVENT` (`pull_request` | `push`);
  - `HEAD_REF` (branch de origem do PR);
  - `MAIN_REF` (padrão `origin/main`);
  - `TARGET` (padrão `HEAD`).
- Roda no diretório do repo. Saída 0 = ok.

- [ ] **Passo 1: escrever os testes que falham, `tests/origem.bats`**

```bash
load helpers

setup() {
  make_sandbox
  R="$SANDBOX/r"
  git init -q -b main "$R"
  cd "$R"
  echo 1 > a && git add a && git commit -qm "c1"
  git branch prod
  echo 2 >> a && git commit -qam "c2"
  git switch -q prod && git merge -q --no-ff main -m "release: c2" && git switch -q main
  export MAIN_REF=main TARGET=prod
  ORIGEM="$REPO_ROOT/ci/origem.sh"
}

@test "prod só com commits do main (e merges): ok" {
  EVENT=push run "$ORIGEM"
  [ "$status" -eq 0 ]
}

@test "commit direto no prod: falha e lista o commit" {
  git switch -q prod && echo x >> a && git commit -qam "direto no prod" && git switch -q main
  EVENT=push run "$ORIGEM"
  [ "$status" -ne 0 ]
  [[ "$output" == *"direto no prod"* ]]
}

@test "PR para prod vindo de feat/*: falha" {
  EVENT=pull_request HEAD_REF=feat/x run "$ORIGEM"
  [ "$status" -ne 0 ]
  [[ "$output" == *"main"* ]]
}

@test "PR para prod vindo do main: ok" {
  EVENT=pull_request HEAD_REF=main run "$ORIGEM"
  [ "$status" -eq 0 ]
}
```

- [ ] **Passo 2: rodar e ver falhar**

Rode: `bats tests/origem.bats`
Esperado: FAIL.

- [ ] **Passo 3: criar `ci/origem.sh`**

```bash
#!/usr/bin/env bash
# origem — regra do GitLab flow: o prod só recebe o que já está no main.
#   - PR para o prod precisa vir do branch main;
#   - todo commit (fora os de merge) alcançável a partir do prod precisa existir no main.
# Sem proteção de branch no GitHub gratuito, é este job que denuncia um push direto no prod.
set -euo pipefail

EVENT=${EVENT:-push}
HEAD_REF=${HEAD_REF:-}
MAIN_REF=${MAIN_REF:-origin/main}
TARGET=${TARGET:-HEAD}

falha() { echo "origem: $*" >&2; exit 1; }

if [[ $EVENT == pull_request && $HEAD_REF != main ]]; then
  falha "PR para o prod precisa vir do main (veio de '$HEAD_REF')"
fi

extras=$(git log --no-merges --format='%h %s' "$MAIN_REF..$TARGET")
if [[ -n $extras ]]; then
  falha "commits no prod que não estão no main (siga feat/* → main → prod):
$extras"
fi
echo "origem: ok — tudo no prod veio do main"
```

Depois: `chmod +x ci/origem.sh`

- [ ] **Passo 4: rodar e ver passar**

Rode: `bats tests/origem.bats && shellcheck -x ci/origem.sh`
Esperado: 4/4 passam e o lint fica limpo.

- [ ] **Passo 5: Commit**

```bash
git add ci/origem.sh tests/origem.bats
git commit -m "ci: job origem garante que o prod só recebe o que está no main"
```

---

### Tarefa 7: Hooks pre-commit e pre-push

**Arquivos:**
- Criar: `ci/hooks/pre-commit`, `ci/hooks/pre-push`, `tests/hooks.bats`

**Interfaces:**
- `pre-push` lê, na entrada padrão, linhas `<ref-local> <sha-local> <ref-remoto> <sha-remoto>`.
  - `JARVIS_PREPUSH_CMD` (padrão `make ci`) define o comando de verificação.
  - `ALLOWED_REFS` (variável no topo) guarda os padrões permitidos.
- `pre-commit` usa o `gitleaks` e o `shellcheck` do `PATH` (com `.ci-bin/bin` na frente).

- [ ] **Passo 1: escrever os testes que falham, `tests/hooks.bats`**

```bash
load helpers

setup() {
  make_sandbox
  R="$SANDBOX/r"
  git init -q -b main "$R"
  cd "$R"
  echo 1 > a && git add a && git commit -qm c1
  git switch -q -c feat/x
  SHA=$(git rev-parse HEAD)
  Z=0000000000000000000000000000000000000000
  PRE_PUSH="$REPO_ROOT/ci/hooks/pre-push"
  PRE_COMMIT="$REPO_ROOT/ci/hooks/pre-commit"
  export JARVIS_PREPUSH_CMD=true
}

push() { printf '%s\n' "$@" | "$PRE_PUSH" origin git@exemplo:repo.git; }

@test "pre-push aceita feat/* e roda a verificação" {
  export JARVIS_PREPUSH_CMD="touch $SANDBOX/rodou"
  run push "refs/heads/feat/x $SHA refs/heads/feat/x $Z"
  [ "$status" -eq 0 ]
  [ -e "$SANDBOX/rodou" ]
}

@test "pre-push recusa main e prod" {
  for b in main prod; do
    run push "refs/heads/feat/x $SHA refs/heads/$b $Z"
    [ "$status" -ne 0 ] || { echo "aceitou $b"; return 1; }
    [[ "$output" == *"use um PR"* ]]
  done
}

@test "pre-push recusa tags e branches fora do padrão" {
  run push "refs/tags/v1 $SHA refs/tags/v1 $Z"
  [ "$status" -ne 0 ]
  run push "refs/heads/feat/x $SHA refs/heads/teste $Z"
  [ "$status" -ne 0 ]
}

@test "pre-push: apagar feat/* remoto é permitido sem rodar verificação" {
  export JARVIS_PREPUSH_CMD=false
  run push "(delete) $Z refs/heads/feat/velho $SHA"
  [ "$status" -eq 0 ]
}

@test "pre-push: apagar main remoto é recusado" {
  run push "(delete) $Z refs/heads/main $SHA"
  [ "$status" -ne 0 ]
}

@test "pre-push: verificação falhando bloqueia" {
  export JARVIS_PREPUSH_CMD=false
  run push "refs/heads/feat/x $SHA refs/heads/feat/x $Z"
  [ "$status" -ne 0 ]
  [[ "$output" == *"make ci"* ]]
}

@test "pre-push: ref diferente do HEAD ou árvore suja é recusado" {
  git switch -q -c feat/outro && echo 2 >> a && git commit -qam c2 && git switch -q feat/x
  OUTRO=$(git rev-parse feat/outro)
  run push "refs/heads/feat/outro $OUTRO refs/heads/feat/outro $Z"
  [ "$status" -ne 0 ]; [[ "$output" == *"checkout"* ]]
  echo sujo >> a
  run push "refs/heads/feat/x $SHA refs/heads/feat/x $Z"
  [ "$status" -ne 0 ]; [[ "$output" == *"commit"* ]]
}

@test "pre-commit: sem gitleaks falha com instrução" {
  mkdir -p "$SANDBOX/bin"
  ln -s "$(command -v shellcheck)" "$SANDBOX/bin/shellcheck"
  for c in git bash sed grep cat dirname basename env; do ln -sf "$(command -v $c)" "$SANDBOX/bin/$c"; done
  PATH="$SANDBOX/bin" run "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"make ferramentas"* ]]
}

@test "pre-commit: gitleaks acusando bloqueia; .sh com erro de shellcheck bloqueia" {
  mkdir -p "$SANDBOX/bin"
  printf '#!/bin/sh\nexit 1\n' > "$SANDBOX/bin/gitleaks"; chmod +x "$SANDBOX/bin/gitleaks"
  echo x > b && git add b
  PATH="$SANDBOX/bin:$PATH" run "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/bin/gitleaks"
  printf '#!/usr/bin/env bash\necho $1\n' > ruim.sh && git add ruim.sh
  PATH="$SANDBOX/bin:$PATH" run "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  printf '#!/usr/bin/env bash\necho "$1"\n' > ruim.sh && git add ruim.sh
  PATH="$SANDBOX/bin:$PATH" run "$PRE_COMMIT"
  [ "$status" -eq 0 ]
}
```

- [ ] **Passo 2: rodar e ver falhar**

Rode: `bats tests/hooks.bats`
Esperado: FAIL.

- [ ] **Passo 3: criar `ci/hooks/pre-commit`**

```bash
#!/usr/bin/env bash
# pre-commit — barra segredos e erros de shellcheck ANTES de virar commit.
# Ativado por `make hooks` (core.hooksPath = ci/hooks). Pular: git commit --no-verify (só emergência).
set -euo pipefail
top=$(git rev-parse --show-toplevel)
export PATH="$top/.ci-bin/bin:$PATH"

falta=()
for c in gitleaks shellcheck; do command -v "$c" >/dev/null || falta+=("$c"); done
if ((${#falta[@]})); then
  echo "pre-commit: faltando ${falta[*]} — rode: make ferramentas" >&2
  exit 1
fi

if ! gitleaks git --staged --redact --no-banner "$top"; then
  echo "pre-commit: possível segredo no commit — remova (segredos vão no .env da VPS)" >&2
  exit 1
fi

arquivos=()
while IFS= read -r f; do
  [[ -f $top/$f && ! -L $top/$f ]] || continue
  if [[ $f == *.sh || $f == bin/* || $f == ci/hooks/* ]]; then arquivos+=("$top/$f"); fi
done < <(git diff --cached --name-only --diff-filter=ACM)
if ((${#arquivos[@]})); then
  shellcheck -x "${arquivos[@]}" || { echo "pre-commit: corrija os avisos do shellcheck" >&2; exit 1; }
fi
```

- [ ] **Passo 4: criar `ci/hooks/pre-push`**

```bash
#!/usr/bin/env bash
# pre-push — 1) recusa push direto em main/prod (só feat/* e fix/*); 2) roda o portão 1 local.
# Sem proteção de branch no GitHub gratuito, este hook faz esse papel na sua máquina.
# Pular: git push --no-verify (só emergência; o CI e o jarvis deploy continuam valendo).
set -euo pipefail

ALLOWED_REFS='^refs/heads/(feat|fix)/[a-z0-9._-]+$'
ZERO=0000000000000000000000000000000000000000
read -r -a CMD <<<"${JARVIS_PREPUSH_CMD:-make ci}"

verificar=0
head=$(git rev-parse HEAD)
while read -r _local_ref local_sha remote_ref _remote_sha; do
  if ! [[ $remote_ref =~ $ALLOWED_REFS ]]; then
    echo "pre-push: push direto para '${remote_ref#refs/heads/}' não é permitido — use um branch feat/* ou fix/* e abra um PR" >&2
    exit 1
  fi
  [[ $local_sha == "$ZERO" ]] && continue   # apagar um feat/* remoto
  if [[ $local_sha != "$head" ]]; then
    echo "pre-push: só envio o branch atual — faça checkout de '${remote_ref#refs/heads/}' antes" >&2
    exit 1
  fi
  verificar=1
done

((verificar)) || exit 0
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "pre-push: há mudanças sem commit — faça commit ou stash antes (o make ci testaria outra coisa)" >&2
  exit 1
fi
cd "$(git rev-parse --show-toplevel)"
"${CMD[@]}" || { echo "pre-push: make ci falhou — corrija antes de enviar" >&2; exit 1; }
```

Depois: `chmod +x ci/hooks/pre-commit ci/hooks/pre-push`

- [ ] **Passo 5: rodar e ver passar**

Rode: `bats tests/hooks.bats && make lint`
Esperado: 9/9 passam e o lint fica limpo.

- [ ] **Passo 6: Commit e ativar os hooks**

```bash
git add ci/hooks tests/hooks.bats
git commit -m "ci: hooks pre-commit (segredos, shellcheck) e pre-push (bloqueia main/prod, roda make ci)"
make hooks
```

---

### Tarefa 8: Workflows, Dependabot e arquivos de política

**Arquivos:**
- Criar: `.github/workflows/portao-1.yml`, `.github/workflows/portao-2.yml`, `.github/dependabot.yml`, `ci/testes-exigidos.txt`, `ci/lynis-minimo.txt`, `tests/workflows.bats`

- [ ] **Passo 1: escrever os testes que falham, `tests/workflows.bats`**

```bash
load helpers

@test "toda ação usada está fixada por SHA de 40 caracteres" {
  run bash -c "grep -hE '^\s*-?\s*uses:' '$REPO_ROOT'/.github/workflows/*.yml | grep -v './.github/' | grep -vE '@[0-9a-f]{40}( |$)'"
  [ -z "$output" ]
}

@test "nenhum workflow usa pull_request_target nem secrets" {
  run grep -lE 'pull_request_target|secrets\.' "$REPO_ROOT"/.github/workflows/*.yml
  [ -z "$output" ]
}

@test "todo checkout usa persist-credentials: false" {
  for f in "$REPO_ROOT"/.github/workflows/*.yml; do
    usos=$(grep -c 'actions/checkout@' "$f" || true)
    pcs=$(grep -c 'persist-credentials: false' "$f" || true)
    [ "$usos" -eq "$pcs" ] || { echo "$f: $usos checkouts, $pcs persist-credentials"; return 1; }
  done
}

@test "permissões do topo são contents: read" {
  for f in "$REPO_ROOT"/.github/workflows/*.yml; do
    grep -qzP 'permissions:\s*\n\s*contents: read' "$f" || { echo "$f"; return 1; }
  done
}

@test "testes-exigidos.txt tem os 7 checks da spec" {
  run grep -vcE '^\s*(#|$)' "$REPO_ROOT/ci/testes-exigidos.txt"
  [ "$output" -eq 7 ]
  for n in 'portao-1 / lint' 'portao-1 / unit' 'portao-1 / secrets' 'portao-1 / workflow-security' origem secrets-historico integracao; do
    grep -qx "$n" "$REPO_ROOT/ci/testes-exigidos.txt" || { echo "faltando: $n"; return 1; }
  done
}

@test "lynis-minimo.txt é um inteiro" {
  run grep -vE '^\s*(#|$)' "$REPO_ROOT/ci/lynis-minimo.txt"
  [[ "$output" =~ ^[0-9]+$ ]]
}
```

- [ ] **Passo 2: rodar e ver falhar**

Rode: `bats tests/workflows.bats`
Esperado: FAIL.

- [ ] **Passo 3: criar `.github/workflows/portao-1.yml`**

```yaml
# Portão 1 — rápido. Roda em PR para o main e é chamado pelo portão 2 (PR e push no prod).
name: portao-1

on:
  pull_request:
    branches: [main]
  workflow_call:

permissions:
  contents: read

jobs:
  lint:
    name: lint
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Ferramentas (versões fixas, checksum conferido)
        run: ci/instalar-ferramentas.sh "$RUNNER_TEMP/ci" shellcheck actionlint
      - name: shellcheck, bash -n e actionlint
        run: |
          export PATH="$RUNNER_TEMP/ci/bin:$PATH"
          make lint
          actionlint

  unit:
    name: unit
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Ferramentas
        run: ci/instalar-ferramentas.sh "$RUNNER_TEMP/ci" bats shellcheck
      - name: bats (inclui caddy validate via Docker e visudo)
        run: |
          export PATH="$RUNNER_TEMP/ci/bin:$PATH"
          make unit

  secrets:
    name: secrets
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
          fetch-depth: 0
      - name: Ferramentas
        run: ci/instalar-ferramentas.sh "$RUNNER_TEMP/ci" gitleaks
      - name: gitleaks (no PR, só os commits do PR)
        env:
          EVENT: ${{ github.event_name }}
          BASE_REF: ${{ github.base_ref }}
        run: |
          export PATH="$RUNNER_TEMP/ci/bin:$PATH"
          if [[ "$EVENT" == pull_request ]]; then
            gitleaks git --redact --no-banner --log-opts="origin/${BASE_REF}..HEAD" .
          else
            gitleaks git --redact --no-banner .
          fi

  workflow-security:
    name: workflow-security
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Ferramentas
        run: ci/instalar-ferramentas.sh "$RUNNER_TEMP/ci" zizmor
      - name: zizmor
        run: |
          export PATH="$RUNNER_TEMP/ci/bin:$PATH"
          zizmor --offline .
```

- [ ] **Passo 4: criar `.github/workflows/portao-2.yml`**

```yaml
# Portão 2 — profundo. Roda em PR para o prod e em todo push no prod.
# O resultado no commit final do prod é o que o `jarvis deploy` consulta na VPS.
name: portao-2

on:
  pull_request:
    branches: [prod]
  push:
    branches: [prod]

permissions:
  contents: read

jobs:
  portao-1:
    uses: ./.github/workflows/portao-1.yml

  origem:
    name: origem
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
          fetch-depth: 0
      - name: prod só recebe o que já está no main
        env:
          EVENT: ${{ github.event_name }}
          HEAD_REF: ${{ github.head_ref }}
        run: ci/origem.sh

  secrets-historico:
    name: secrets-historico
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
          fetch-depth: 0
      - name: Ferramentas
        run: ci/instalar-ferramentas.sh "$RUNNER_TEMP/ci" gitleaks
      - name: gitleaks em todo o histórico
        run: |
          export PATH="$RUNNER_TEMP/ci/bin:$PATH"
          gitleaks git --redact --no-banner .

  integracao:
    name: integracao
    needs: [portao-1, origem]
    runs-on: ubuntu-24.04
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Provisionar 00→60 duas vezes nesta VM descartável e auditar
        run: ci/integracao.sh
      - name: Relatório do Lynis
        if: always()
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: lynis
          path: ${{ runner.temp }}/lynis-report.dat
          if-no-files-found: ignore
          retention-days: 30
```

- [ ] **Passo 5: criar `.github/dependabot.yml`, `ci/testes-exigidos.txt` e `ci/lynis-minimo.txt`**

`.github/dependabot.yml`:
```yaml
# Atualiza as ações dos workflows (fixadas por SHA). Os PRs vão para o main e passam pelo portão 1.
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    target-branch: main
    schedule:
      interval: weekly
    cooldown:
      default-days: 14
    commit-message:
      prefix: ci
```

`ci/testes-exigidos.txt`:
```
# Check runs que o `jarvis deploy` exige verdes no commit do prod (um por linha, nome exato da API).
# O deploy lê esta lista da versão JÁ IMPLANTADA na VPS: um commit não afrouxa as próprias exigências.
portao-1 / lint
portao-1 / unit
portao-1 / secrets
portao-1 / workflow-security
origem
secrets-historico
integracao
```

`ci/lynis-minimo.txt`:
```
# Índice mínimo de endurecimento do Lynis no job integracao. Só sobe, nunca desce.
# Começa em 0; depois do primeiro run, ajuste para (índice medido - 2) — Tarefa 12.
0
```

- [ ] **Passo 6: rodar os testes e as ferramentas reais**

Rode: `bats tests/workflows.bats && make ci`
Esperado: os 6 testes passam. No `make ci`, actionlint e zizmor ficam sem achados, e o gitleaks no histórico local fica sem vazamentos.
- Se o zizmor apontar um achado, **corrija o workflow** (não silencie) e rode de novo.
- Se o gitleaks acusar um falso positivo comprovado num arquivo de documentação, crie `.gitleaks.toml` com um `[allowlist]` restrito àquele caminho e a um comentário explicando o motivo. Registre isso no ledger.

- [ ] **Passo 7: Commit**

```bash
git add .github ci/testes-exigidos.txt ci/lynis-minimo.txt tests/workflows.bats
if [[ -f .gitleaks.toml ]]; then git add .gitleaks.toml; fi
git commit -m "ci: portões 1 e 2, Dependabot e políticas de deploy"
```

---

### Tarefa 9: Integração (`ci/integracao.sh` e auditoria)

**Arquivos:**
- Criar: `ci/integracao.sh`, `tests/integracao/auditoria.bats`

**Interfaces:**
- Só roda com `GITHUB_ACTIONS=true` e `RUNNER_ENVIRONMENT=github-hosted`. Fora disso, aborta.
- Usa `RUNNER_TEMP` e `GITHUB_STEP_SUMMARY`. Escreve `$RUNNER_TEMP/lynis-report.dat`.
- `bats tests` (unitários) **não** entra em `tests/integracao/` (o bats não é recursivo sem `-r`).

Este código só é exercitado de verdade na Tarefa 12, no GitHub. Aqui, o critério de pronto é lint limpo mais a recusa fora do CI.

- [ ] **Passo 1: criar `ci/integracao.sh`**

```bash
#!/usr/bin/env bash
# integracao — provisiona ESTA máquina com 00→60, roda tudo de novo (idempotência) e audita.
# Só numa VM descartável do GitHub Actions: o script altera a máquina inteira (SSH, firewall, usuários).
set -euo pipefail

if [[ ${GITHUB_ACTIONS:-} != true || ${RUNNER_ENVIRONMENT:-} != github-hosted ]]; then
  echo "integracao.sh só roda numa VM descartável do GitHub Actions — ele reconfigura a máquina inteira" >&2
  exit 1
fi

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
ADMIN=$(id -un)
TOOLS="$RUNNER_TEMP/ci"
grupo() { echo "::group::$*"; }
fim() { echo "::endgroup::"; }

grupo "ferramentas"
"$REPO/ci/instalar-ferramentas.sh" "$TOOLS" bats lynis
fim

grupo "repo em /opt/jarvis (admin: $ADMIN)"
sudo rm -rf /opt/jarvis
sudo cp -a "$REPO" /opt/jarvis
sudo chown -R "$ADMIN:$ADMIN" /opt/jarvis
sudo sed -i "s/^ADMIN_USER=.*/ADMIN_USER=\${ADMIN_USER:-$ADMIN}/" /opt/jarvis/provision/vars.sh
fim

JARVIS_CI=1
JARVIS_DASHBOARD_PASSWORD="ci-$(openssl rand -hex 16)"
export JARVIS_CI JARVIS_DASHBOARD_PASSWORD
rodar() { sudo --preserve-env=JARVIS_CI,JARVIS_DASHBOARD_PASSWORD "/opt/jarvis/provision/$1"; }

env_falso() {
  # .env com valores FALSOS (sem segredos no CI). O gateway não é iniciado.
  sudo -u hermes tee /var/lib/hermes/.hermes/.env >/dev/null <<'EOF'
# jarvis:env — valores falsos do CI
OPENAI_API_KEY=ci-falso
TELEGRAM_BOT_TOKEN=ci-falso
TELEGRAM_ALLOWED_USERS=1
TELEGRAM_HOME_CHANNEL=1
GITHUB_TOKEN=ci-falso
EOF
}

provisionar() {
  rodar 00-bootstrap.sh
  rodar 10-sistema.sh
  rodar 20-wireguard.sh
  rodar 30-dns-caddy.sh
  rodar 40-hermes.sh
  if ! sudo -u hermes grep -q '^OPENAI_API_KEY=.' /var/lib/hermes/.hermes/.env; then
    env_falso
    rodar 40-hermes.sh
  fi
  rodar 50-docker-rootless.sh
  rodar 60-backup.sh
}

grupo "provisionamento — 1ª vez"
provisionar
fim

grupo "provisionamento — 2ª vez (idempotência)"
provisionar
fim

grupo "dispositivo de teste na VPN"
sudo jarvis-peer add ci-teste >/dev/null
sudo wg show wg0 peers | grep -q .
fim

grupo "auditoria"
PATH="$TOOLS/bin:$PATH" bats /opt/jarvis/tests/integracao
fim

grupo "Lynis"
lynis_dir=$(dirname "$(readlink -f "$TOOLS/bin/lynis")")
sudo chown -R root:root "$lynis_dir"   # o Lynis exige seus arquivos com dono root
(cd "$lynis_dir" && sudo ./lynis audit system --quick --no-colors --report-file /tmp/lynis-report.dat >/dev/null)
sudo install -m 644 /tmp/lynis-report.dat "$RUNNER_TEMP/lynis-report.dat"
indice=$(grep '^hardening_index=' "$RUNNER_TEMP/lynis-report.dat" | cut -d= -f2)
minimo=$(grep -vE '^[[:space:]]*(#|$)' /opt/jarvis/ci/lynis-minimo.txt)
echo "Lynis: índice de endurecimento $indice (mínimo exigido: $minimo)"
echo "### Lynis: índice de endurecimento **$indice** (mínimo $minimo)" >>"$GITHUB_STEP_SUMMARY"
fim
((indice >= minimo)) || { echo "Lynis: índice $indice abaixo do mínimo $minimo" >&2; exit 1; }
```

Depois: `chmod +x ci/integracao.sh`

- [ ] **Passo 2: criar `tests/integracao/auditoria.bats`**

```bash
# Auditoria pós-provisionamento. Roda SÓ no job integracao (VM descartável), como o admin com sudo.
# Portas públicas aceitas: SSH, WireGuard e os clientes DHCP (IPv4 68, IPv6 546).

setup() {
  HUID=$(id -u hermes)
}

as_hermes() {
  sudo -u hermes env HOME=/var/lib/hermes XDG_RUNTIME_DIR="/run/user/$HUID" \
    DOCKER_HOST="unix:///run/user/$HUID/docker.sock" \
    PATH=/var/lib/hermes/.local/bin:/usr/local/bin:/usr/bin:/bin "$@"
}

portas_publicas() {
  sudo ss -Htuln | awk '{print $1, $5}' |
    grep -vE ' (127\.|\[::1\]|\[::ffff:127\.|10\.8\.0\.1:)' |
    awk '{n = split($2, a, ":"); print $1 "/" a[n]}' | sort -u
}

@test "só SSH, WireGuard e DHCP escutam fora do loopback e da VPN" {
  for p in $(portas_publicas); do
    case $p in tcp/22 | udp/51820 | udp/68 | udp/546) ;; *) echo "porta inesperada: $p"; return 1 ;; esac
  done
}

@test "firewall ativo" {
  sudo ufw status | grep -q 'Status: active'
}

@test "SSH recusa root e senha" {
  sudo sshd -T | grep -qx 'permitrootlogin no'
  sudo sshd -T | grep -qx 'passwordauthentication no'
}

@test "hermes não tem sudo geral nem lê /opt/jarvis" {
  run as_hermes sudo -n true
  [ "$status" -ne 0 ]
  run as_hermes ls /opt/jarvis
  [ "$status" -ne 0 ]
}

@test "jarvis-expose via sudo recusa entradas maliciosas" {
  for args in "../x 8100" "Exemplo 8100" "exemplo 70000" "exemplo 18446744073709559716"; do
    # shellcheck disable=SC2086
    run as_hermes sudo -n /usr/local/sbin/jarvis-expose $args
    [ "$status" -ne 0 ] || { echo "aceitou: $args"; return 1; }
  done
  run ls /etc/caddy/apps.d/
  [ -z "$output" ]
}

@test "jarvis-expose publica app válido só na VPN e unexpose remove" {
  run as_hermes sudo -n /usr/local/sbin/jarvis-expose exemplo 8101
  [ "$status" -eq 0 ]
  code=$(curl -s -o /dev/null -w '%{http_code}' --resolve exemplo.jarvis.lan:80:10.8.0.1 http://exemplo.jarvis.lan/)
  [ "$code" = 502 ]   # Caddy roteou; não há app na porta 8101
  run as_hermes sudo -n /usr/local/sbin/jarvis-unexpose exemplo
  [ "$status" -eq 0 ]
  [ ! -e /etc/caddy/apps.d/exemplo.caddy ]
}

@test "dashboard pede senha (401) pela VPN" {
  code=$(curl -s -o /dev/null -w '%{http_code}' --resolve hermes.jarvis.lan:80:10.8.0.1 http://hermes.jarvis.lan/)
  [ "$code" = 401 ]
}

@test "API admin do Caddy inacessível (nem localhost:2019 nem o socket para o hermes)" {
  run curl -s --max-time 3 http://localhost:2019/config/
  [ "$status" -ne 0 ]
  run as_hermes curl -s --max-time 3 --unix-socket /run/caddy/admin.sock http://x/config/
  [ "$status" -ne 0 ]
}

@test "ataque de link simbólico do hermes real não afeta /usr/local/sbin" {
  antes=$(stat -c '%U:%G %a' /usr/local/sbin)
  as_hermes bash -c 'cd ~/.hermes && { [ -e skills ] && mv skills skills.ci-bak || true; } && ln -sfn /usr/local/sbin skills'
  run jarvis import
  [ "$status" -ne 0 ]; [[ "$output" == *"link simbólico"* ]]
  run jarvis apply --force
  [ "$status" -ne 0 ]
  [ "$(stat -c '%U:%G %a' /usr/local/sbin)" = "$antes" ]
  [ -x /usr/local/sbin/jarvis-expose ]
  as_hermes bash -c 'cd ~/.hermes && rm skills && { [ -e skills.ci-bak ] && mv skills.ci-bak skills || true; }'
}

@test "link do config.yaml para /etc/shadow não vaza no import" {
  as_hermes bash -c 'cd ~/.hermes && { [ -e config.yaml ] && mv config.yaml config.yaml.ci-bak || true; } && ln -sfn /etc/shadow config.yaml'
  run jarvis import
  [ "$status" -ne 0 ]
  run grep -rq 'root:' /opt/jarvis/hermes/
  [ "$status" -ne 0 ]
  as_hermes bash -c 'cd ~/.hermes && rm config.yaml && { [ -e config.yaml.ci-bak ] && mv config.yaml.ci-bak config.yaml || true; }'
}

@test "Docker rootless funciona para o hermes e o Docker de root está parado" {
  run as_hermes docker run --rm hello-world
  [ "$status" -eq 0 ]
  run systemctl is-active docker
  [ "$output" != active ]
}

@test "serviços do Hermes habilitados, backup gerado e dispositivo na VPN" {
  systemctl is-enabled hermes-gateway hermes-dashboard
  systemctl is-active --quiet jarvis-backup.timer
  ls /var/backups/jarvis/*.tar.zst
  sudo jarvis-peer list | grep -q ci-teste
}
```

- [ ] **Passo 3: lint e recusa fora do CI**

Rode:
```bash
make lint
bash -n tests/integracao/auditoria.bats || true   # .bats não é bash puro; o bats valida ao rodar
ci/integracao.sh; echo "saída: $?"
```

Esperado: o lint fica limpo, e o `ci/integracao.sh` sai com 1 e a mensagem "só roda numa VM descartável do GitHub Actions". **Não** rode com as variáveis do GitHub falsificadas.

- [ ] **Passo 4: Commit**

```bash
git add ci/integracao.sh tests/integracao/auditoria.bats
git commit -m "ci: integração provisiona 00→60 duas vezes em VM descartável e audita (incl. Lynis)"
```

---

### Tarefa 10: Documentação

**Arquivos:**
- Criar: `docs/aprendizado/80-ci-e-fluxo-git.md`
- Modificar: `docs/operacao.md`, `README.md`, `docs/plans/2026-10-17-jarvis-base.md`

- [ ] **Passo 1: escrever `docs/aprendizado/80-ci-e-fluxo-git.md`**

Seções obrigatórias:
1. **O fluxo:** o diagrama `feat/* → main → prod → jarvis deploy` e a regra "upstream first".
2. **Os dois portões:** cada job, o que ele pega e um exemplo de falha que ele mostraria.
3. **Hooks:** `make ferramentas` + `make hooks` (uma vez por clone), o que cada hook faz e o `--no-verify` como exceção consciente.
4. **Preflight e `jarvis check`:** a tabela de regras, com um exemplo de saída com dois erros.
5. **`jarvis deploy`:** passo a passo, o que ele recusa e por quê. Como criar o token: GitHub → Settings → Developer settings → Fine-grained tokens → Repository access: só `renpv/jarvis` → Permissions: **Checks: Read-only** → validade de 1 ano. Na VPS:
   ```bash
   install -d -m 700 ~/.config/jarvis
   (umask 077; cat > ~/.config/jarvis/github-token)   # cole o token, Enter, Ctrl+D
   jarvis check
   ```
6. **Mudança feita no dashboard (`jarvis import`) no fluxo novo:**
   ```bash
   cd /opt/jarvis && jarvis import
   git switch -c feat/hermes-<assunto> && git commit -am "hermes: <assunto>" && git push -u origin HEAD
   git switch prod   # o /opt/jarvis volta ao prod; abra o PR para o main e depois o release
   ```
   Até o release chegar, **não rode `jarvis apply`**: ele aplicaria a versão antiga do repo por cima da mudança. O `jarvis diff` mostra a diferença.
7. **Lendo uma falha:** `gh run list`, `gh run view <id> --log-failed`, o artefato `lynis` e o resumo do índice.
8. **Atualizar ferramentas (mensal):** para cada uma, ver o release mais recente com pelo menos 14 dias, baixar, conferir `sha256sum` contra o checksum publicado (quando houver), atualizar `ci/ferramentas.txt` num `feat/*`, e rodar `make ferramentas && make ci`.
9. **Subir o mínimo do Lynis:** onde ver as sugestões (o artefato), endurecer, e subir `ci/lynis-minimo.txt`.

- [ ] **Passo 2: atualizar `docs/operacao.md`**
- Na tabela "Dia a dia", acrescente as linhas `| Trazer novidades do prod (só com testes verdes) | jarvis deploy |` e `| Conferir tudo sem mudar nada | jarvis check |`.
- Na seção "2. Mudar a configuração", troque o passo 1 por "No computador: branch `feat/<assunto>`, commit, `git push -u origin HEAD`, PR para o `main`, e depois PR `main` → `prod` (veja 80-ci-e-fluxo-git.md)".
- Troque o passo 2 por:
  ```bash
  jarvis deploy   # confere os testes, mostra o que entra e sugere os próximos passos
  ```
- Ao fim da seção 2, acrescente a nota do `jarvis import` (item 6 do Passo 1).

- [ ] **Passo 3: atualizar o `README.md`.** Depois da seção "Pastas", acrescente:

```markdown
## Fluxo de trabalho

`feat/<assunto>` → PR para `main` (portão 1) → PR `main` → `prod` (portão 2) → `jarvis deploy` na VPS.
Primeira vez num clone: `make ferramentas && make hooks`. Detalhes: [docs/aprendizado/80-ci-e-fluxo-git.md](docs/aprendizado/80-ci-e-fluxo-git.md).
```

E na seção "Testes", troque o bloco por:

```bash
make ferramentas   # uma vez: ferramentas fixadas por checksum em .ci-bin/
make test          # lint + bats
make ci            # o portão 1 inteiro, igual ao GitHub
```

- [ ] **Passo 4: adaptar a Fase B do plano base.** Rode este script (ele faz as substituições exatas e falha se algum trecho não for encontrado):

```bash
python3 - <<'PY'
p = 'docs/plans/2026-10-17-jarvis-base.md'
s = open(p).read()
subs = [
    ("cd /opt/jarvis && git pull && sudo provision/", "jarvis deploy; cd /opt/jarvis && sudo provision/"),
    ("cd /opt/jarvis && git pull && jarvis apply", "jarvis deploy   # oferece o jarvis apply quando hermes/ mudou"),
    ("ssh -t root@IP_DA_VPS 'bash /root/provision/00-bootstrap.sh'",
     "ssh -t root@IP_DA_VPS 'bash /root/provision/00-bootstrap.sh'   # clona o branch prod"),
]
for old, new in subs:
    assert old in s, old
    s = s.replace(old, new)
nota = """# FASE B — na VPS (guiada; Renato executa)

> **Fluxo Git (desde o plano 2026-10-19-ci-e-fluxo-git):** onde esta fase diz "Commit e push",
> leia: branch `feat/<assunto>` → commit → `git push -u origin HEAD` → PR para o `main`. Docs não
> precisam de release. Mudanças que a VPS precisa (scripts, `hermes/`) vão também no PR `main` → `prod`,
> e chegam à VPS com `jarvis deploy`. Commits feitos **na VPS** (depois de `jarvis import`) seguem a
> receita de `docs/aprendizado/80-ci-e-fluxo-git.md`, item 6. Logo depois do bootstrap (Tarefa 12),
> crie o token de deploy (mesmo documento, item 5) e rode `jarvis check`.
"""
old_h = "# FASE B — na VPS (guiada; Renato executa)\n"
assert old_h in s
s = s.replace(old_h, nota, 1)
open(p, 'w').write(s)
PY
grep -c 'jarvis deploy' docs/plans/2026-10-17-jarvis-base.md
```

Esperado: a contagem final é ≥ 6 e não há `AssertionError`.

- [ ] **Passo 5: Commit**

```bash
git add docs README.md
git commit -m "docs: guia de CI e fluxo Git; operação e Fase B usam jarvis deploy"
```

---

# FASE B — no GitHub

### Tarefa 11: Primeiro PR para o `main` (portão 1 de verdade)

- [ ] **Passo 1: suíte completa local**

Rode: `make ci`
Esperado: verde.

- [ ] **Passo 2: confirmar com Renato e enviar.** É uma ação externa: pergunte antes. Com o "sim":

```bash
git push -u origin feat/ci-fluxo-git     # o pre-push roda make ci de novo
gh pr create --repo renpv/jarvis --base main --head feat/ci-fluxo-git \
  --title "CI e fluxo Git (GitLab flow com main e prod)" \
  --body-file <(printf 'Implementa docs/specs/2026-10-18-ci-e-fluxo-git-design.md (plano docs/plans/2026-10-19-ci-e-fluxo-git.md).\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n')
```

- [ ] **Passo 3: acompanhar o portão 1**

Rode: `gh pr checks --repo renpv/jarvis --watch`
Esperado: `lint`, `unit`, `secrets` e `workflow-security` verdes. Se algum falhar: `gh run view <id> --log-failed`, corrija num commit no mesmo branch e envie de novo. **Não** desligue nenhuma checagem para passar.

- [ ] **Passo 4 [RENATO]: merge do PR** (*merge commit*).

---

### Tarefa 12: Criar o `prod` e fazer o portão 2 passar

- [ ] **Passo 1: ajustar o repo (pedir confirmação a Renato antes)**

```bash
gh api -X PATCH repos/renpv/jarvis -F delete_branch_on_merge=true -F allow_squash_merge=false -F allow_rebase_merge=false
sha=$(gh api repos/renpv/jarvis/git/ref/heads/main --jq .object.sha)
gh api repos/renpv/jarvis/git/refs -f ref=refs/heads/prod -f sha="$sha"
```

Esperado: o branch `prod` existe, e o push dele dispara o `portao-2`.

- [ ] **Passo 2: acompanhar o portão 2**

Rode: `gh run list --repo renpv/jarvis --branch prod --limit 3` e depois `gh run watch <id>`.
Esperado: todos os jobs verdes.

Se a `integracao` falhar, o problema está nos scripts de provisionamento, e é exatamente para isso que ela existe:
1. `gh run view <id> --log-failed`;
2. reproduza o raciocínio, corrija num `fix/<assunto>` → PR para o `main` → `gh api` para avançar o `prod` (`-X PATCH repos/renpv/jarvis/git/refs/heads/prod -f sha=<novo main>`; avanço rápido, sem `force`).

Registre cada correção no ledger.

- [ ] **Passo 3: conferir os nomes dos check runs**

```bash
sha=$(gh api repos/renpv/jarvis/git/ref/heads/prod --jq .object.sha)
gh api "repos/renpv/jarvis/commits/$sha/check-runs?per_page=100" --jq '.check_runs[].name' | sort
```

Esperado: a lista contém exatamente as 7 linhas de `ci/testes-exigidos.txt`. Se o GitHub nomear diferente (ex.: sem o prefixo `portao-1 / `), corrija o arquivo e o teste `tests/workflows.bats` num `fix/nomes-checks`, e leve até o `prod`.

- [ ] **Passo 4: fixar o mínimo do Lynis.** Leia o índice no resumo do run (`gh run view <id>`) e grave `índice - 2` em `ci/lynis-minimo.txt` num `fix/lynis-minimo`. Leve até o `prod` pelo fluxo normal: PR para o `main`, depois PR `main` → `prod`.

---

### Tarefa 13: Aceite

**Arquivos:**
- Criar: `docs/aceite-ci.md`

Para cada critério da spec (seção 11), registre ✅/❌, a data, o link do run ou PR e como foi verificado. Os PRs de teste (critérios 1 a 4) são abertos de branches `feat/aceite-*` e **fechados sem merge**, com o branch apagado.

- [ ] **Passo 1: critérios 1 a 4 (PRs vermelhos de propósito).** Para cada um, crie o branch, faça o commit indicado e envie com `git push --no-verify` (o hook barraria localmente, e queremos ver o CI barrar):
  1. `feat/aceite-lint`: um `provision/zz-teste.sh` com `echo $1` → `lint` vermelho.
  2. `feat/aceite-secrets`: um `docs/teste.txt` com `token = "ghp_` seguido de 36 letras `a` e `"` (monte o valor no terminal com `printf`, nunca cole um token real) → `secrets` vermelho.
  3. `feat/aceite-zizmor`: troque o SHA do `actions/checkout` no `portao-1.yml` por `@v4` → `workflow-security` vermelho (e `unit` vermelho em `tests/workflows.bats`).
  4. `feat/aceite-origem`: abra um PR com base `prod` e head `feat/aceite-origem` → `origem` vermelho.

  Depois de cada um: `gh pr close <n> --delete-branch`.

- [ ] **Passo 2: critério 7 (pre-commit).** Num branch local descartável, crie um arquivo com o mesmo token falso, faça `git add` e `git commit`. O commit precisa ser bloqueado. Depois apague o branch.

- [ ] **Passo 3: critério 9 (pre-push).** `git push origin HEAD:main` → recusado com "use um PR".

- [ ] **Passo 4: critério 10 (preflight).** Localmente: `WG_PORT=99999 TIMEZONE=America/Fortalesa bash -c 'source provision/lib.sh; preflight'` lista os 2 problemas e sai com 1.

- [ ] **Passo 5: critério 8 (Dependabot).** Aguarde o primeiro PR do Dependabot (até 1 semana) e registre o resultado do portão 1. Pode ficar pendente no documento até lá.

- [ ] **Passo 6: critérios 5, 6 e 11.**
  - **5:** o run verde do portão 2 (Tarefa 12).
  - **6 e 11:** são verificados na VPS, durante a Fase B do plano base. Na Tarefa 12 de lá, depois do token: `jarvis check` mostra tudo ✅. Na primeira mudança real: `jarvis deploy` avança. Um teste de recusa: num `fix/*`, faça um release com um teste quebrado de propósito; o deploy recusa; depois reverta.

- [ ] **Passo 7: Commit e PR**

```bash
git switch -c feat/aceite-ci origin/main
git add docs/aceite-ci.md && git commit -m "docs: aceite do CI e fluxo Git"
git push -u origin HEAD && gh pr create --repo renpv/jarvis --base main --fill
```

---

## Nota: `~/.ssh/config` do WSL

O `IdentityFile C:/Users/renpv/.ssh/id_renpv` não existe dentro do WSL. Para o `git push` funcionar sem o `GIT_SSH_COMMAND`, troque essa linha por `IdentityFile ~/.ssh/id_renpv`. É decisão de Renato; o plano não altera esse arquivo.

## Autorrevisão

- **Cobertura da spec:**
  - §3 fluxo → T6, T7, T12; §4.1 → T8 (portão 1); §4.2 → T8 (portão 2); §4.3 → T3, T9; §4.4 → T8, T12
  - §5 deploy → T5; §6 ferramentas e manutenção → T1, T8, T10; §7 hooks → T1 (Makefile), T7
  - §8 preflight → T2, T3, T4; §9 custos → documentado em T10; §10 riscos → mitigados em T5, T6, T7 e T8
  - §11 critérios 1–11 → T13
- **Desvios da spec, conscientes:**
  - O job `integracao` não recebe `actions: read`: o upload de artefato não precisa dessa permissão (menos permissão).
  - O pre-push também recusa tags e branches fora de `feat/*` e `fix/*`, como diz a seção 7.2.
  - O Dependabot usa `cooldown` de 14 dias, para não adotar versões recém-publicadas.
- **Placeholders:** `<assunto>`, `<id>` e `<n>` são valores do momento da execução, explicados em cada passo. O mínimo do Lynis é 0 por definição até a medição (T12, Passo 4).
- **Consistência:**
  - `preflight`, `check_vars`, `check_os`, `DEPLOY_TOKEN_FILE`, `JARVIS_HTTP`, `GITHUB_API`, `DEPLOY_BRANCH`, `JARVIS_PREPUSH_CMD`, `FERRAMENTAS_LIST` e `JARVIS_FETCH` têm os mesmos nomes em todas as tarefas.
  - Os nomes dos checks são os mesmos em T8, T12 e `ci/testes-exigidos.txt`.
