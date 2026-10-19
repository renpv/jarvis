# Auditoria pós-provisionamento. Roda SÓ no job integracao (VM descartável), como o admin com sudo.
# Portas públicas aceitas: SSH, WireGuard e os clientes DHCP (IPv4 68, IPv6 546).

setup() {
  HUID=$(id -u hermes)
}

as_hermes() {
  sudo -u hermes env -i LANG=C.UTF-8 HOME=/var/lib/hermes XDG_RUNTIME_DIR="/run/user/$HUID" \
    DOCKER_HOST="unix:///run/user/$HUID/docker.sock" \
    PATH=/var/lib/hermes/.local/bin:/usr/local/bin:/usr/bin:/bin "$@"
}

portas_publicas() {
  sudo ss -Htuln | awk '{print $1, $5}' |
    grep -vE ' (127\.|\[::1\]|\[::ffff:127\.|10\.8\.0\.1:)' |
    awk '{n = split($2, a, ":"); print $1 "/" a[n]}' | sort -u
}

@test "só SSH, WireGuard e DHCP escutam fora do loopback e da VPN" {
  for p in $(portas_publicas); do
    case $p in tcp/22 | udp/51820 | udp/68 | udp/546) ;; *) echo "porta inesperada: $p"; return 1 ;; esac
  done
}

@test "firewall ativo" {
  sudo ufw status | grep -q 'Status: active'
}

@test "SSH recusa root e senha" {
  sudo sshd -T | grep -qx 'permitrootlogin no'
  sudo sshd -T | grep -qx 'passwordauthentication no'
}

@test "hermes não tem sudo geral nem lê /opt/jarvis" {
  run as_hermes sudo -n true
  [ "$status" -ne 0 ]
  run as_hermes ls /opt/jarvis
  [ "$status" -ne 0 ]
}

@test "jarvis-expose via sudo recusa entradas maliciosas" {
  for args in "../x 8100" "Exemplo 8100" "exemplo 70000" "exemplo 18446744073709559716"; do
    # shellcheck disable=SC2086
    run as_hermes sudo -n /usr/local/sbin/jarvis-expose $args
    [ "$status" -ne 0 ] || { echo "aceitou: $args"; return 1; }
  done
  run ls /etc/caddy/apps.d/
  [ -z "$output" ]
}

@test "jarvis-expose publica app válido só na VPN e unexpose remove" {
  run as_hermes sudo -n /usr/local/sbin/jarvis-expose exemplo 8101
  [ "$status" -eq 0 ]
  code=$(curl -s -o /dev/null -w '%{http_code}' --resolve exemplo.jarvis.lan:80:10.8.0.1 http://exemplo.jarvis.lan/)
  [ "$code" = 502 ]   # Caddy roteou; não há app na porta 8101
  run as_hermes sudo -n /usr/local/sbin/jarvis-unexpose exemplo
  [ "$status" -eq 0 ]
  [ ! -e /etc/caddy/apps.d/exemplo.caddy ]
}

@test "dashboard pede senha (401) pela VPN" {
  code=$(curl -s -o /dev/null -w '%{http_code}' --resolve hermes.jarvis.lan:80:10.8.0.1 http://hermes.jarvis.lan/)
  [ "$code" = 401 ]
}

@test "API admin do Caddy inacessível (nem localhost:2019 nem o socket para o hermes)" {
  run curl -s --max-time 3 http://localhost:2019/config/
  [ "$status" -ne 0 ]
  run as_hermes curl -s --max-time 3 --unix-socket /run/caddy/admin.sock http://x/config/
  [ "$status" -ne 0 ]
}

@test "ataque de link simbólico do hermes real não afeta /usr/local/sbin" {
  antes=$(stat -c '%U:%G %a' /usr/local/sbin)
  as_hermes bash -c 'cd ~/.hermes && { [ -e skills ] && mv skills skills.ci-bak || true; } && ln -sfn /usr/local/sbin skills'
  run jarvis import
  [ "$status" -ne 0 ]; [[ "$output" == *"link simbólico"* ]]
  run jarvis apply --force
  [ "$status" -ne 0 ]
  [ "$(stat -c '%U:%G %a' /usr/local/sbin)" = "$antes" ]
  [ -x /usr/local/sbin/jarvis-expose ]
  as_hermes bash -c 'cd ~/.hermes && rm skills && { [ -e skills.ci-bak ] && mv skills.ci-bak skills || true; }'
}

@test "link do config.yaml para /etc/shadow não vaza no import" {
  as_hermes bash -c 'cd ~/.hermes && { [ -e config.yaml ] && mv config.yaml config.yaml.ci-bak || true; } && ln -sfn /etc/shadow config.yaml'
  run jarvis import
  [ "$status" -ne 0 ]
  run grep -rq 'root:' /opt/jarvis/hermes/
  [ "$status" -ne 0 ]
  as_hermes bash -c 'cd ~/.hermes && rm config.yaml && { [ -e config.yaml.ci-bak ] && mv config.yaml.ci-bak config.yaml || true; }'
}

@test "Docker rootless funciona para o hermes e o Docker de root está parado" {
  run as_hermes docker run --rm hello-world
  [ "$status" -eq 0 ]
  run systemctl is-active docker
  [ "$output" != active ]
}

@test "serviços do Hermes habilitados, backup gerado e dispositivo na VPN" {
  systemctl is-enabled hermes-gateway hermes-dashboard
  systemctl is-active --quiet jarvis-backup.timer
  ls /var/backups/jarvis/*.tar.zst
  sudo jarvis-peer list | grep -q ci-teste
}
