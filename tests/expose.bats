load helpers

setup() {
  make_sandbox
  export APPS_DIR="$SANDBOX/apps.d"
  mkdir -p "$APPS_DIR"
  export VALIDATE_CMD=true RELOAD_CMD="touch $SANDBOX/reloaded"
  EXPOSE="$REPO_ROOT/bin/jarvis-expose"
  UNEXPOSE="$REPO_ROOT/bin/jarvis-unexpose"
}

@test "publica app válido usando o modelo fixo e recarrega" {
  run "$EXPOSE" notas 8101
  [ "$status" -eq 0 ]
  expected=$'http://notas.jarvis.lan {\n\tbind 10.8.0.1\n\treverse_proxy 127.0.0.1:8101\n}'
  [ "$(cat "$APPS_DIR/notas.caddy")" = "$expected" ]
  [ -f "$SANDBOX/reloaded" ]
}

@test "recusa nomes inválidos ou reservados sem criar arquivo" {
  for n in ../etc Notas a app_1 'a b' hermes admin -app app- "$(printf 'x%.0s' {1..40})"; do
    run "$EXPOSE" "$n" 8101
    [ "$status" -ne 0 ] || { echo "aceitou: $n"; return 1; }
  done
  [ -z "$(ls -A "$APPS_DIR")" ]
}

@test "recusa portas fora da faixa ou não numéricas" {
  for p in 80 8099 8200 81x0 '' -1 08101; do
    run "$EXPOSE" notas "$p"
    [ "$status" -ne 0 ] || { echo "aceitou porta: $p"; return 1; }
  done
}

@test "recusa porta já usada por outro app" {
  "$EXPOSE" um 8101
  run "$EXPOSE" dois 8101
  [ "$status" -ne 0 ]
  [[ "$output" == *"8101"* ]]
  [ ! -e "$APPS_DIR/dois.caddy" ]
}

@test "publicar de novo o mesmo app troca a porta" {
  "$EXPOSE" notas 8101
  run "$EXPOSE" notas 8102
  [ "$status" -eq 0 ]
  grep -q '127.0.0.1:8102$' "$APPS_DIR/notas.caddy"
}

@test "configuração inválida desfaz e mantém a versão anterior" {
  "$EXPOSE" notas 8101
  export VALIDATE_CMD=false
  run "$EXPOSE" notas 8102
  [ "$status" -ne 0 ]
  grep -q '127.0.0.1:8101$' "$APPS_DIR/notas.caddy"
  run "$EXPOSE" novo 8103
  [ "$status" -ne 0 ]
  [ ! -e "$APPS_DIR/novo.caddy" ]
}

@test "unexpose remove o app e recarrega" {
  "$EXPOSE" notas 8101
  rm -f "$SANDBOX/reloaded"
  run "$UNEXPOSE" notas
  [ "$status" -eq 0 ]
  [ ! -e "$APPS_DIR/notas.caddy" ]
  [ -f "$SANDBOX/reloaded" ]
}

@test "unexpose de app inexistente ou nome inválido falha" {
  run "$UNEXPOSE" nada
  [ "$status" -ne 0 ]
  run "$UNEXPOSE" ../Caddyfile
  [ "$status" -ne 0 ]
}

@test "constantes do jarvis-expose batem com vars.sh" {
  source "$REPO_ROOT/provision/vars.sh"
  grep -qx "DOMAIN=$DOMAIN" "$EXPOSE"
  grep -qx "BIND=$WG_SERVER_IP" "$EXPOSE"
  grep -qx "PORT_MIN=$APP_PORT_MIN" "$EXPOSE"
  grep -qx "PORT_MAX=$APP_PORT_MAX" "$EXPOSE"
}
