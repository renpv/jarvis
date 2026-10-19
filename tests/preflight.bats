load helpers

setup() {
  make_sandbox
  source "$REPO_ROOT/provision/lib.sh"
  printf 'ID=ubuntu\nVERSION_ID="24.04"\n' > "$SANDBOX/os-ok"
  export OS_RELEASE="$SANDBOX/os-ok"
}

invalido() {   # invalido VAR VALOR TRECHO_ESPERADO
  printf -v "$1" '%s' "$2"
  run check_vars
  [ "$status" -ne 0 ] || { echo "aceitou $1=$2"; return 1; }
  [[ "$output" == *"$3"* ]] || { echo "mensagem sem '$3': $output"; return 1; }
}

@test "valores padrão do vars.sh passam" {
  run check_vars
  [ "$status" -eq 0 ]
}

@test "usuários: formato, iguais entre si ou root" {
  invalido ADMIN_USER "Renato" ADMIN_USER
  ADMIN_USER=renpv
  invalido HERMES_USER "" HERMES_USER
  HERMES_USER=renpv; run check_vars; [[ "$output" == *"diferentes"* ]]
  HERMES_USER=root; run check_vars; [[ "$output" == *"root"* ]]
}

@test "caminhos precisam ser absolutos, sem .. e sem espaço" {
  invalido HERMES_DIR "var/lib/hermes" HERMES_DIR
  HERMES_DIR=/var/lib/hermes
  invalido JARVIS_DIR "/opt/../etc" JARVIS_DIR
  JARVIS_DIR=/opt/jarvis
  invalido JARVIS_DIR "/opt/meu jarvis" JARVIS_DIR
}

@test "GitHub: slug dono/repo e URL do github" {
  invalido GITHUB_SLUG "renpv" GITHUB_SLUG
  GITHUB_SLUG=renpv/jarvis
  invalido GITHUB_REPO "git@gitlab.com:renpv/jarvis.git" GITHUB_REPO
}

@test "TIMEZONE precisa existir" {
  invalido TIMEZONE "America/Fortalesa" TIMEZONE
  TIMEZONE=America/Fortaleza
  invalido TIMEZONE "../../etc/passwd" TIMEZONE
}

@test "DOMAIN e WG_IF" {
  invalido DOMAIN "jarvis" DOMAIN
  DOMAIN=jarvis.lan
  invalido DOMAIN "Jarvis.LAN" DOMAIN
  DOMAIN=jarvis.lan
  invalido WG_IF "wg 0" WG_IF
}

@test "portas: limites 1..65535" {
  WG_PORT=65535; run check_vars; [ "$status" -eq 0 ]
  invalido WG_PORT 65536 WG_PORT
  WG_PORT=51820
  invalido WG_PORT 0 WG_PORT
  WG_PORT=51820
  invalido DASHBOARD_PORT "91a9" DASHBOARD_PORT
}

@test "faixa de apps e porta do dashboard" {
  APP_PORT_MIN=8199 APP_PORT_MAX=8100
  run check_vars; [[ "$output" == *"APP_PORT_MIN"* ]]
  APP_PORT_MIN=8100 APP_PORT_MAX=8199 DASHBOARD_PORT=8100
  run check_vars; [ "$status" -ne 0 ]; [[ "$output" == *"DASHBOARD_PORT"* ]]
  DASHBOARD_PORT=8200
  run check_vars; [ "$status" -eq 0 ]
}

@test "rede WireGuard" {
  invalido WG_NET "10.8" WG_NET
  WG_NET=10.8.0
  invalido WG_NET "10.8.300" WG_NET
  WG_NET=10.8.0
  invalido WG_SERVER_IP "10.9.0.1" WG_SERVER_IP
  WG_SERVER_IP=10.8.0.254; run check_vars; [ "$status" -eq 0 ]
  invalido WG_SERVER_IP "10.8.0.255" WG_SERVER_IP
  WG_SERVER_IP=10.8.0.1
  invalido WG_SERVER_IP "10.8.0.0" WG_SERVER_IP
  WG_SERVER_IP=10.8.0.1
  invalido WG_SERVER_IP "10.8.0.256" WG_SERVER_IP
}

@test "WG_ENDPOINT vazio, IPv4 ou nome DNS" {
  WG_ENDPOINT=""; run check_vars; [ "$status" -eq 0 ]
  WG_ENDPOINT=203.0.113.5; run check_vars; [ "$status" -eq 0 ]
  WG_ENDPOINT=vpn.exemplo.com; run check_vars; [ "$status" -eq 0 ]
  invalido WG_ENDPOINT "203.0.113" WG_ENDPOINT
}

@test "preflight lista todos os problemas de uma vez" {
  TIMEZONE=America/Fortalesa WG_PORT=99999
  run preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *"TIMEZONE"* ]]
  [[ "$output" == *"WG_PORT"* ]]
  [[ "$output" == *"2 problema"* ]]
}

@test "preflight para antes de qualquer efeito" {
  cat > "$SANDBOX/script.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$REPO_ROOT/provision/lib.sh"
preflight
touch "$SANDBOX/sentinela"
EOF
  chmod +x "$SANDBOX/script.sh"
  WG_PORT=99999 run "$SANDBOX/script.sh"
  [ "$status" -ne 0 ]
  [ ! -e "$SANDBOX/sentinela" ]
  run "$SANDBOX/script.sh"
  [ "$status" -eq 0 ]
  [ -e "$SANDBOX/sentinela" ]
}

@test "requisito os" {
  run preflight os; [ "$status" -eq 0 ]
  printf 'ID=debian\nVERSION_ID="12"\n' > "$SANDBOX/os-ruim"
  OS_RELEASE="$SANDBOX/os-ruim" run preflight os
  [ "$status" -ne 0 ]; [[ "$output" == *"Ubuntu 24.04"* ]]
}

@test "requisitos cmd, user, ci-env e desconhecido" {
  run preflight cmd:comando-que-nao-existe-xyz; [ "$status" -ne 0 ]
  run preflight "user:usuario-que-nao-existe-xyz"; [ "$status" -ne 0 ]
  run preflight "user:$(id -un)"; [ "$status" -eq 0 ]
  JARVIS_CI=1 run preflight ci-env:SENHA_TESTE_XYZ; [ "$status" -ne 0 ]
  run preflight ci-env:SENHA_TESTE_XYZ; [ "$status" -eq 0 ]
  run preflight requisito-inventado; [ "$status" -ne 0 ]
}

@test "requisito sudo-admin" {
  SUDO_USER=outro run preflight sudo-admin
  [ "$status" -ne 0 ]
  SUDO_USER=$ADMIN_USER run preflight sudo-admin
  [ "$status" -eq 0 ]
}
