load helpers

setup() {
  make_sandbox
  source "$REPO_ROOT/provision/lib.sh"
  WG_SERVER_PRIVKEY=chave-de-teste
  HERMES_UID=1234
  PUBLIC_IP=203.0.113.10 CHATWOOT_TLS="" CADDY_UID=111 CHATWOOT_UID=222
  CADDY_VARS=(WG_SERVER_IP DOMAIN DASHBOARD_PORT PUBLIC_IP CHATWOOT_DOMAIN CHATWOOT_PORT CHATWOOT_TLS)
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
  # timeout: um Docker local travado não pode prender o pre-push para sempre
  hash=$(timeout 120 docker run --rm caddy:2.10 caddy hash-password --plaintext teste)
  timeout 120 docker run --rm -v "$SANDBOX/caddy:/etc/caddy:ro" \
    -e DASHBOARD_USER=renpv -e DASHBOARD_HASH="$hash" -e CHATWOOT_GATE_USER=portao -e CHATWOOT_GATE_HASH="$hash" \
    caddy:2.10 caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
}

@test "Caddyfile é válido sem nenhum app publicado" {
  timeout 20 docker info >/dev/null 2>&1 || skip "docker indisponível"
  mkdir -p "$SANDBOX/caddy/apps.d"
  render "$REPO_ROOT/system/caddy/Caddyfile.tpl" "${CADDY_VARS[@]}" > "$SANDBOX/caddy/Caddyfile"
  run caddy_validate
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "Caddyfile é válido com um app publicado pelo jarvis-expose" {
  timeout 20 docker info >/dev/null 2>&1 || skip "docker indisponível"
  mkdir -p "$SANDBOX/caddy/apps.d"
  render "$REPO_ROOT/system/caddy/Caddyfile.tpl" "${CADDY_VARS[@]}" > "$SANDBOX/caddy/Caddyfile"
  APPS_DIR="$SANDBOX/caddy/apps.d" "$REPO_ROOT/bin/jarvis-expose" exemplo 8101
  run caddy_validate
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "API admin do Caddy fica num socket só do usuário caddy (não em localhost)" {
  run render "$REPO_ROOT/system/caddy/Caddyfile.tpl" "${CADDY_VARS[@]}"
  [[ "$output" == *"admin unix//run/caddy/admin.sock"* ]]
  [[ "$output" != *"localhost:2019"* ]]
  run render "$REPO_ROOT/system/systemd/caddy-override.conf.tpl" WG_IF
  [[ "$output" == *"RuntimeDirectory=caddy"* ]]
  [[ "$output" == *"RuntimeDirectoryMode=0700"* ]]
}

@test "dashboard: Caddy recusa Origin estranha e reescreve a certa para o bind do dashboard" {
  run render "$REPO_ROOT/system/caddy/Caddyfile.tpl" "${CADDY_VARS[@]}"
  [[ "$output" == *"not header Origin http://hermes.jarvis.lan"* ]]
  [[ "$output" == *"respond @outra_origem"*"403"* ]]
  [[ "$output" == *"header_up Origin http://127.0.0.1:9119"* ]]
}

@test "Caddy: nada global prende o bind nem desliga o HTTPS; cada site declara onde escuta" {
  run render "$REPO_ROOT/system/caddy/Caddyfile.tpl" "${CADDY_VARS[@]}"
  output=$(grep -vE '^[[:space:]]*#' <<<"$output")
  [[ "$output" != *"default_bind"* ]]
  [[ "$output" != *"auto_https off"* ]]
  sites=$(grep -cE '^[^#[:space:]{}][^{]*\{$' <<<"$output")
  binds=$(grep -cE '^[[:space:]]+bind ' <<<"$output")
  [ "$sites" -ge 2 ] && [ "$sites" -eq "$binds" ] || { echo "sites=$sites binds=$binds"; return 1; }
}

@test "Caddy: dashboard e apps só na VPN; Chatwoot público com HTTPS no IP público" {
  run render "$REPO_ROOT/system/caddy/Caddyfile.tpl" "${CADDY_VARS[@]}"
  grep -A1 -x 'http://hermes.jarvis.lan {' <<<"$output" | grep -qx $'\tbind 10.8.0.1'
  grep -A1 -x 'atendimento.renpv.com.br {' <<<"$output" | grep -qx $'\tbind 203.0.113.10'
  [[ "$output" == *"reverse_proxy 127.0.0.1:3000"* ]]
  # a 80 pública precisa de site próprio (desafio do Let's Encrypt e redirect para https)
  grep -A2 -x 'http://atendimento.renpv.com.br {' <<<"$output" | grep -qx $'\tbind 203.0.113.10'
  grep -A2 -x 'http://atendimento.renpv.com.br {' <<<"$output" | grep -qx $'\tredir https://{host}{uri} 308'

}

@test "Caddy: criação do primeiro admin e o super_admin do Chatwoot pedem uma senha própria" {
  run render "$REPO_ROOT/system/caddy/Caddyfile.tpl" "${CADDY_VARS[@]}"
  bloco=$(sed -n '/^atendimento.renpv.com.br {/,/^}/p' <<<"$output")
  [[ "$bloco" == *"@restrito path /installation* /super_admin*"* ]]
  [[ "$bloco" == *"basic_auth @restrito"* ]]
  # credencial própria e aleatória: a senha do dashboard não fica exposta a força bruta na internet
  [[ "$bloco" == *'{$CHATWOOT_GATE_USER} {$CHATWOOT_GATE_HASH}'* ]]
  [[ "$bloco" != *'DASHBOARD_'* ]]
}

@test "Caddy: no CI o Chatwoot usa tls internal (não gasta o limite do Let's Encrypt do domínio real)" {
  CHATWOOT_TLS="tls internal"
  run render "$REPO_ROOT/system/caddy/Caddyfile.tpl" "${CADDY_VARS[@]}"
  sed -n '/^atendimento.renpv.com.br {/,/^}/p' <<<"$output" | grep -qx $'\ttls internal'
}

@test "Caddyfile com Chatwoot em tls internal é válido" {
  timeout 20 docker info >/dev/null 2>&1 || skip "docker indisponível"
  mkdir -p "$SANDBOX/caddy/apps.d"
  CHATWOOT_TLS="tls internal"
  render "$REPO_ROOT/system/caddy/Caddyfile.tpl" "${CADDY_VARS[@]}" > "$SANDBOX/caddy/Caddyfile"
  run caddy_validate
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "nftables: só caddy, chatwoot e root abrem a porta local do Chatwoot (o hermes não pula o Caddy)" {
  CADDY_UID=111 CHATWOOT_UID=222
  run render "$REPO_ROOT/system/nftables/chatwoot-porta.nft.tpl" CHATWOOT_PORT CADDY_UID CHATWOOT_UID
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"type filter hook output"* ]]
  [[ "$output" == *"ip daddr 127.0.0.1 tcp dport 3000 meta skuid != { 0, 111, 222 } reject with tcp reset"* ]]
  [[ "$output" == *"ip6 daddr ::1 tcp dport 3000 meta skuid != { 0, 111, 222 } reject with tcp reset"* ]]
  timeout 20 docker info >/dev/null 2>&1 || skip "docker indisponível"
  # nft -c precisa de CAP_NET_ADMIN: valida num container descartável, como o caddy validate
  run bash -c "printf '%s\\n' \"\$1\" | timeout 180 docker run --rm -i --cap-add NET_ADMIN alpine:3.20 sh -c 'apk add -q nftables >/dev/null && nft -c -f -'" _ "$output"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "regra da porta do Chatwoot falha fechada: carrega antes das sessões e serviços, sem ExecStop" {
  f="$REPO_ROOT/system/systemd/jarvis-chatwoot-porta.service"
  grep -qx 'DefaultDependencies=no' "$f"
  grep -qE '^Before=.*systemd-logind\.service' "$f"
  grep -qE '^Before=.*systemd-user-sessions\.service' "$f"
  grep -qE '^Before=.*hermes-gateway\.service' "$f"
  grep -qE '^Before=.*caddy\.service' "$f"
  ! grep -q '^ExecStop=' "$f"
  grep -qx 'ExecReload=/usr/sbin/nft -f /etc/jarvis/chatwoot-porta.nft' "$f"
  ! grep -q 'systemctl restart jarvis-chatwoot-porta' "$REPO_ROOT/provision/70-chatwoot.sh"
}
