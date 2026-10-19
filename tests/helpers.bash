# tests/helpers.bash — funções comuns aos testes bats.
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

make_sandbox() {
  SANDBOX="$(mktemp -d)"
}

teardown() {
  if [[ -n ${SANDBOX:-} ]]; then rm -rf "$SANDBOX"; fi
}

# Commits feitos pelos testes (repos temporários) não dependem da configuração do usuário.
export GIT_AUTHOR_NAME=teste GIT_AUTHOR_EMAIL=teste@exemplo.invalid
export GIT_COMMITTER_NAME=teste GIT_COMMITTER_EMAIL=teste@exemplo.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
