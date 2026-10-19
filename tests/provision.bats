load helpers

@test "todo script de provisionamento chama preflight antes de qualquer alteração" {
  for f in "$REPO_ROOT"/provision/[0-9]*.sh; do
    primeira=$(grep -nE '^(preflight|apt_get|apt_install|install |useradd|usermod|systemctl|ufw|timedatectl|mkdir|chmod|ln )' "$f" | head -1)
    [[ $primeira == *preflight* ]] || { echo "$(basename "$f"): primeira ação não é preflight: $primeira"; return 1; }
  done
}

@test "requisitos de preflight de cada script batem com a spec" {
  grep -qx 'preflight os root' "$REPO_ROOT/provision/00-bootstrap.sh"
  grep -qx 'preflight os root sudo-admin admin-keys' "$REPO_ROOT/provision/10-sistema.sh"
  grep -qx 'preflight os root' "$REPO_ROOT/provision/20-wireguard.sh"
  grep -qx 'preflight os root "iface:$WG_IF" ci-env:JARVIS_DASHBOARD_PASSWORD' "$REPO_ROOT/provision/30-dns-caddy.sh"
  grep -qx 'preflight os root' "$REPO_ROOT/provision/40-hermes.sh"
  grep -qx 'preflight os root "user:$HERMES_USER"' "$REPO_ROOT/provision/50-docker-rootless.sh"
  grep -qx 'preflight os root "user:$HERMES_USER"' "$REPO_ROOT/provision/60-backup.sh"
}

@test "bootstrap clona o branch prod" {
  grep -q 'git clone -b prod' "$REPO_ROOT/provision/00-bootstrap.sh"
}

@test "nenhum script usa require_root solto (o preflight cobre)" {
  run grep -l '^require_root' "$REPO_ROOT"/provision/[0-9]*.sh
  [ -z "$output" ]
}

@test "50 instala explicitamente as dependências do Docker rootless (sem depender de Recommends)" {
  grep -E '^apt_install .*docker-ce-rootless-extras' "$REPO_ROOT/provision/50-docker-rootless.sh" | grep -q slirp4netns
  grep -E '^apt_install .*docker-ce-rootless-extras' "$REPO_ROOT/provision/50-docker-rootless.sh" | grep -q dbus-user-session
}

@test "50 mostra o journal do docker rootless quando ele não sobe" {
  grep -q 'journalctl --user' "$REPO_ROOT/provision/50-docker-rootless.sh"
}
