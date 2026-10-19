# CI e fluxo Git

Como uma mudança sai do seu computador e chega à VPS, e o que a verifica no caminho.
Spec: [2026-10-18-ci-e-fluxo-git-design.md](../specs/2026-10-18-ci-e-fluxo-git-design.md).

## 1. O fluxo (GitLab flow)

```
feat/x ──PR──► main ──PR (release: …)──► prod ──jarvis deploy──► VPS (/opt/jarvis)
fix/y  ──PR──┘
```

- **`main`** — o que está integrado e testado.
- **`prod`** — o que a VPS deve rodar.
- **Trabalho** sempre em `feat/<assunto>` ou `fix/<assunto>`, criado a partir do `main`.
- **Upstream first:** até uma correção urgente segue `fix/*` → `main` → `prod`. Nada vai direto ao `prod`.

No GitHub gratuito, repos privados não têm proteção de branch. Por isso a disciplina é garantida em três lugares:

| Onde | O quê |
|---|---|
| Seu computador | hook **pre-push** recusa push para `main`/`prod` |
| GitHub Actions | job **origem** fica vermelho se o `prod` tiver commit que não está no `main` |
| VPS | **`jarvis deploy`** só traz commit do `prod` com todos os testes verdes |

## 2. Os dois portões

### Portão 1 — em todo PR para o `main` (≈3 min)

| Job | Pega… | Exemplo de falha |
|---|---|---|
| `lint` | erro de bash, sintaxe, workflow inválido | `echo $1` sem aspas (SC2086) |
| `unit` | os testes bats (inclui `caddy validate` real e `visudo`) | `jarvis apply` sobrescrevendo mudança do dashboard |
| `secrets` | segredo nos commits do PR | um token colado num arquivo |
| `workflow-security` | ação por tag, permissão sobrando, injeção em `${{ }}` | `uses: actions/checkout@v4` |

### Portão 2 — em PR para o `prod` e em todo push no `prod` (≈15–25 min)

| Job | Pega… |
|---|---|
| `portao-1 / *` | os quatro acima, de novo |
| `origem` | PR para o `prod` que não vem do `main`; commit no `prod` que não está no `main` |
| `secrets-historico` | segredo em **qualquer** ponto do histórico |
| `integracao` | roda `00`→`60` **duas vezes** numa VM Ubuntu 24.04 descartável e audita (portas, sudo do hermes, ataque de link simbólico, API do Caddy, Docker rootless, Lynis) |

O resultado do portão 2 **no commit final do `prod`** é o que o `jarvis deploy` consulta.

## 3. Hooks locais

Uma vez por clone:

```bash
make ferramentas   # baixa as versões fixadas (ci/ferramentas.txt) em .ci-bin/, conferindo SHA-256
make hooks         # git config core.hooksPath ci/hooks
```

- **pre-commit** — gitleaks no que está sendo commitado e shellcheck nos scripts do commit.
- **pre-push** — recusa `main`, `prod`, tags e qualquer branch fora de `feat/*` e `fix/*`. Exige árvore limpa e o branch atual. Roda `make ci`.
- **Exceção consciente:** `git commit --no-verify` / `git push --no-verify`. Use só em emergência. O CI e o deploy continuam valendo.

## 4. Preflight e `jarvis check`

Todo script de `provision/` começa com `preflight`, que valida o `vars.sh` e os requisitos do script **antes** de mudar qualquer coisa, e lista todos os problemas de uma vez:

```
ERRO preflight encontrou 2 problema(s) — nada foi alterado:
  - TIMEZONE inexistente: 'America/Fortalesa' (veja timedatectl list-timezones)
  - WG_PORT inválida: '99999' (inteiro de 1 a 65535)
```

As regras estão na spec, seção 8.1. `jarvis check` faz a mesma validação sob demanda e mostra ✅/❌. Ele também cobre o sistema, os comandos, o `.env` e o token de deploy, e nunca altera nada.

## 5. `jarvis deploy`

Na VPS, como `renpv`:

```bash
jarvis deploy
```

1. Recusa se o `/opt/jarvis` não estiver no `prod` ou tiver mudanças locais.
2. Busca o `prod`; se não houver nada novo, para.
3. Recusa se o histórico do `prod` tiver sido reescrito.
4. Consulta no GitHub os check runs do commit. Todos os listados em `ci/testes-exigidos.txt` **da versão já implantada** precisam estar `completed/success`. Re-runs: vale o mais recente.
5. Mostra os commits e arquivos, pede `s/N` e avança por fast-forward.
6. Sugere os scripts a rodar de novo. Se `hermes/` mudou, oferece o `jarvis apply`. Scripts de root nunca rodam sozinhos.

### Criar o token de deploy (uma vez, logo depois do bootstrap)

1. GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate new token.
2. **Repository access:** Only select repositories → `renpv/jarvis`.
3. **Permissions → Repository permissions → Checks: Read-only.** Nada mais.
4. **Expiration:** 1 ano. Anote a data.
5. Na VPS:
   ```bash
   install -d -m 700 ~/.config/jarvis
   (umask 077; cat > ~/.config/jarvis/github-token)   # cole o token, Enter, Ctrl+D
   jarvis check
   ```

O token só lê resultados de testes de um repositório. Ele fica na sua home (modo 600), fora do alcance do `hermes`.

## 6. Mudança feita no dashboard (`jarvis import`) no fluxo novo

```bash
cd /opt/jarvis && jarvis import
git switch -c feat/hermes-<assunto> && git commit -am "hermes: <assunto>" && git push -u origin HEAD
git switch prod   # o /opt/jarvis volta ao prod; abra o PR para o main e depois o release
```

Até o release chegar à VPS, **não rode `jarvis apply`**: ele aplicaria a versão antiga do repo por cima da mudança do dashboard. Use `jarvis diff` para ver a diferença.

## 7. Lendo uma falha

```bash
gh run list --repo renpv/jarvis --limit 5
gh run view <id> --repo renpv/jarvis --log-failed
gh run download <id> --repo renpv/jarvis -n lynis   # relatório do Lynis
```

- **No PR:** a aba *Checks* mostra cada job. O resumo do run mostra o índice do Lynis.
- **Para reproduzir localmente:** `make test` (lint e unit) ou `make ci` (portão 1 inteiro).
- **A `integracao` só roda no CI:** ela reconfigura a máquina inteira.

## 8. Atualizar ferramentas (mensal)

1. Para cada linha de `ci/ferramentas.txt`, veja o release mais recente **com pelo menos 14 dias**:
   `gh api repos/<dono>/<repo>/releases --jq '.[0:3][] | "\(.tag_name) \(.published_at)"'`.
2. Baixe o arquivo e calcule `sha256sum`. Se o projeto publicar um arquivo de checksums, confira se bate.
3. Atualize a linha (versão, URL, sha256 e caminho do binário) num `feat/ferramentas-<mês>`.
4. `make ferramentas && make ci` e depois o PR. As ações dos workflows ficam por conta do Dependabot.

## 9. Subir o mínimo do Lynis

O artefato `lynis` de cada run do portão 2 lista sugestões de endurecimento (`suggestion[]=`).
1. Escolha uma sugestão.
2. Aplique-a nos scripts.
3. Confira que o índice subiu.
4. Suba `ci/lynis-minimo.txt` para o novo valor menos 2.

O mínimo **só sobe**.
