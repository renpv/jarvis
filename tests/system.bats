load helpers

setup() {
  make_sandbox
  source "$REPO_ROOT/provision/lib.sh"
  WG_SERVER_PRIVKEY=chave-de-teste
  HERMES_UID=1234
}

@test "existem todos os modelos esperados" {
  for f in apt/20auto-upgrades fail2ban/jail.local ssh/00-jarvis.conf.tpl wireguard/wg0.conf.tpl \
           dnsmasq/jarvis.conf.tpl caddy/Caddyfile.tpl sudoers/hermes.tpl \
           systemd/caddy-override.conf.tpl systemd/dnsmasq-override.conf.tpl \
           systemd/hermes-gateway.service.tpl systemd/hermes-dashboard.service.tpl \
           systemd/jarvis-backup.service systemd/jarvis-backup.timer; do
    [ -f "$REPO_ROOT/system/$f" ] || { echo "faltando: system/$f"; return 1; }
  done
}

@test "todos os .tpl renderizam sem sobrar placeholder" {
  for tpl in $(find "$REPO_ROOT/system" -name '*.tpl'); do
    vars=$(grep -oE '@[A-Z][A-Z0-9_]*@' "$tpl" | tr -d @ | sort -u)
    run render "$tpl" $vars
    [ "$status" -eq 0 ] || { echo "falhou: $tpl: $output"; return 1; }
  done
}

@test "arquivos sem .tpl não têm placeholder" {
  run bash -c "find '$REPO_ROOT/system' -type f ! -name '*.tpl' -exec grep -lE '@[A-Z][A-Z0-9_]*@' {} +"
  [ -z "$output" ]
}

@test "unidades do Hermes rodam como hermes com DOCKER_HOST do rootless" {
  run render "$REPO_ROOT/system/systemd/hermes-gateway.service.tpl" HERMES_USER HERMES_DIR HERMES_UID
  [[ "$output" == *"User=hermes"* ]]
  [[ "$output" == *"DOCKER_HOST=unix:///run/user/1234/docker.sock"* ]]
  [[ "$output" == *"ExecStart=/var/lib/hermes/.local/bin/hermes gateway run"* ]]
  [[ "$output" != *"NoNewPrivileges="* ]]
}

@test "dashboard escuta só em 127.0.0.1" {
  run render "$REPO_ROOT/system/systemd/hermes-dashboard.service.tpl" HERMES_USER HERMES_DIR HERMES_UID DASHBOARD_PORT
  [[ "$output" == *"--host 127.0.0.1 --port 9119 --no-open"* ]]
}

@test "sudoers do hermes é válido e só libera expose/unexpose" {
  command -v visudo >/dev/null || skip "visudo indisponível"
  render "$REPO_ROOT/system/sudoers/hermes.tpl" HERMES_USER > "$SANDBOX/hermes"
  run visudo -cf "$SANDBOX/hermes"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(grep -v '^#' "$SANDBOX/hermes" | grep -c .)" -eq 1 ]
  grep -qx 'hermes ALL=(root) NOPASSWD: /usr/local/sbin/jarvis-expose, /usr/local/sbin/jarvis-unexpose' "$SANDBOX/hermes"
}

caddy_validate() {
  local hash
  hash=$(docker run --rm caddy:2.10 caddy hash-password --plaintext teste)
  docker run --rm -v "$SANDBOX/caddy:/etc/caddy:ro" \
    -e DASHBOARD_USER=renpv -e DASHBOARD_HASH="$hash" \
    caddy:2.10 caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
}

@test "Caddyfile é válido sem nenhum app publicado" {
  docker info >/dev/null 2>&1 || skip "docker indisponível"
  mkdir -p "$SANDBOX/caddy/apps.d"
  render "$REPO_ROOT/system/caddy/Caddyfile.tpl" WG_SERVER_IP DOMAIN DASHBOARD_PORT > "$SANDBOX/caddy/Caddyfile"
  run caddy_validate
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "Caddyfile é válido com um app publicado pelo jarvis-expose" {
  docker info >/dev/null 2>&1 || skip "docker indisponível"
  mkdir -p "$SANDBOX/caddy/apps.d"
  render "$REPO_ROOT/system/caddy/Caddyfile.tpl" WG_SERVER_IP DOMAIN DASHBOARD_PORT > "$SANDBOX/caddy/Caddyfile"
  APPS_DIR="$SANDBOX/caddy/apps.d" "$REPO_ROOT/bin/jarvis-expose" exemplo 8101
  run caddy_validate
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "API admin do Caddy fica num socket só do usuário caddy (não em localhost)" {
  run render "$REPO_ROOT/system/caddy/Caddyfile.tpl" WG_SERVER_IP DOMAIN DASHBOARD_PORT
  [[ "$output" == *"admin unix//run/caddy/admin.sock"* ]]
  [[ "$output" != *"localhost:2019"* ]]
  run render "$REPO_ROOT/system/systemd/caddy-override.conf.tpl" WG_IF
  [[ "$output" == *"RuntimeDirectory=caddy"* ]]
  [[ "$output" == *"RuntimeDirectoryMode=0700"* ]]
}
