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
