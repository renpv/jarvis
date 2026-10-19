# tests/helpers.bash — funções comuns aos testes bats.
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

make_sandbox() {
  SANDBOX="$(mktemp -d)"
}

teardown() {
  if [[ -n ${SANDBOX:-} ]]; then rm -rf "$SANDBOX"; fi
}
