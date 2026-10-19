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
  cp "$REPO_ROOT/ci/origem.sh" "$WORK/ci/"
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
  export HERMES_USER="$(id -un)" ADMIN_USER=admin-teste SUDO="" HSUDO="" SYSTEMCTL=":"
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

@test "arquivo novo não versionado (ex.: skill do jarvis import) também bloqueia" {
  novo_commit docs/x.md
  verdes
  mkdir -p "$JARVIS_REPO/hermes/skills/jarvis/nova"
  echo nova > "$JARVIS_REPO/hermes/skills/jarvis/nova/SKILL.md"
  run "$JARVIS" deploy
  [ "$status" -ne 0 ]
  [[ "$output" == *"mudanças locais"* ]]
}

@test "commit no prod que não está no main: recusa mesmo com testes verdes" {
  antes=$(git -C "$JARVIS_REPO" rev-parse HEAD)
  echo direto >> "$WORK/docs-direto.md"
  git -C "$WORK" add -A && git -C "$WORK" commit -qm "direto no prod"
  git -C "$WORK" push -q origin HEAD:prod
  verdes
  run bash -c "printf 's\n' | '$JARVIS' deploy"
  [ "$status" -ne 0 ]
  [[ "$output" == *"direto no prod"* ]]
  [ "$(git -C "$JARVIS_REPO" rev-parse HEAD)" = "$antes" ]
}

@test "deploy roda o preflight (GITHUB_SLUG inválido)" {
  novo_commit docs/x.md
  verdes
  GITHUB_SLUG=invalido run bash -c "printf 'n\n' | '$JARVIS' deploy"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GITHUB_SLUG"* ]]
}
