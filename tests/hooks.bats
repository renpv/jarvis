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
