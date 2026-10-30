load helpers

setup() {
  make_sandbox
  source "$REPO_ROOT/provision/lib.sh"
  COMPOSE="$REPO_ROOT/system/chatwoot/compose.yaml"
}

@test "compose: toda imagem tem versão e digest fixos" {
  imgs=$(grep -E '^[[:space:]]+image:' "$COMPOSE" | awk '{print $2}')
  [ "$(wc -l <<<"$imgs")" -eq 3 ]   # chatwoot (rails e sidekiq, pela âncora), postgres, redis
  while read -r i; do
    [[ $i =~ ^[a-z0-9/._-]+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$ ]] || { echo "sem tag+digest: $i"; return 1; }
    [[ $i != *:latest@* ]] || { echo "latest: $i"; return 1; }
  done <<<"$imgs"
}

@test "compose: só o Rails publica porta, e só em 127.0.0.1" {
  [ "$(grep -cE '^[[:space:]]+(ports|expose):' "$COMPOSE")" -eq 1 ]
  run grep -A1 -E '^[[:space:]]+ports:' "$COMPOSE"
  [[ "$output" == *'- "127.0.0.1:${CHATWOOT_PORT}:3000"'* ]] || { echo "$output"; return 1; }
  sed -n '/^  rails:/,/^  sidekiq:/p' "$COMPOSE" | grep -q 'ports:'
}

@test "compose: segredos vêm do .env, nada de senha no arquivo" {
  grep -q 'env_file: .env' "$COMPOSE"
  run grep -niE '(password|secret)[^:]*:[[:space:]]*[^$[:space:]]' "$COMPOSE"
  [ -z "$output" ] || { echo "$output"; return 1; }
  grep -q -- '--requirepass' "$COMPOSE"
}

@test "compose: cadastro aberto desligado, HTTPS forçado e URL pública certa" {
  grep -qE 'ENABLE_ACCOUNT_SIGNUP: "?false"?' "$COMPOSE"
  grep -qE 'FORCE_SSL: "?true"?' "$COMPOSE"
  grep -q 'FRONTEND_URL: https://${CHATWOOT_DOMAIN}' "$COMPOSE"
}

@test "compose é válido para o docker compose" {
  timeout 20 docker info >/dev/null 2>&1 || skip "docker indisponível"
  cp "$COMPOSE" "$SANDBOX/compose.yaml"
  printf 'CHATWOOT_DOMAIN=x.example\nCHATWOOT_PORT=3000\nSECRET_KEY_BASE=a\nPOSTGRES_PASSWORD=b\nREDIS_PASSWORD=c\n' > "$SANDBOX/.env"
  run timeout 60 docker compose -f "$SANDBOX/compose.yaml" --project-directory "$SANDBOX" config -q
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "vars: domínio, porta e usuário do Chatwoot são validados" {
  CHATWOOT_DOMAIN="Atendimento" CHATWOOT_PORT=99999 CHATWOOT_USER=hermes PUBLIC_IP=1.2.3
  run check_vars
  [ "$status" -ne 0 ]
  [[ "$output" == *"CHATWOOT_DOMAIN inválido"* ]]
  [[ "$output" == *"CHATWOOT_PORT inválida"* ]]
  [[ "$output" == *"CHATWOOT_USER"* ]]
  [[ "$output" == *"PUBLIC_IP inválido"* ]]
}

@test "env_garantir acrescenta só o que falta e nunca troca valor existente" {
  f="$SANDBOX/env"
  printf 'A=1\nB=\n' > "$f"
  env_garantir "$f" A novo
  env_garantir "$f" B gerado
  env_garantir "$f" C 3
  [ "$(cat "$f")" = $'A=1\nB=gerado\nC=3' ]
}
