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
