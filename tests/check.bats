load helpers

setup() {
  make_sandbox
  export JARVIS_REPO="$REPO_ROOT"
  export HERMES_HOME="$SANDBOX/live/.hermes" HERMES_USER="$(id -un)" ADMIN_USER=admin-teste SUDO="" HSUDO=""
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
