load helpers

setup() {
  source "$REPO_ROOT/provision/lib.sh"
}

@test ".env.example declara cada variável exigida pelo jarvis, sem valor" {
  required=$(sed -nE 's/^REQUIRED_ENV=\((.*)\)$/\1/p' "$REPO_ROOT/bin/jarvis")
  [ -n "$required" ]
  for v in $required; do
    grep -qx "${v}=" "$REPO_ROOT/.env.example" || { echo "faltando ou com valor: $v"; return 1; }
  done
}

@test ".env.example não tem nenhuma variável preenchida" {
  run grep -nE '^[A-Z_]+=.+' "$REPO_ROOT/.env.example"
  [ "$status" -eq 1 ]
}

@test ".env.example começa com o marcador usado pelo 40-hermes.sh" {
  head -1 "$REPO_ROOT/.env.example" | grep -q '^# jarvis:env'
}

@test "nenhum arquivo versionado (fora de tests/) contém padrão de token" {
  cd "$REPO_ROOT"
  run bash -c "git ls-files -z -- . ':!tests' | xargs -0 grep -lE '$SECRET_RE' --"
  [ -z "$output" ]
}
