#!/usr/bin/env bash
# integracao — provisiona ESTA máquina com 00→60, roda tudo de novo (idempotência) e audita.
# Só numa VM descartável do GitHub Actions: o script altera a máquina inteira (SSH, firewall, usuários).
set -euo pipefail

if [[ ${GITHUB_ACTIONS:-} != true || ${RUNNER_ENVIRONMENT:-} != github-hosted ]]; then
  echo "integracao.sh só roda numa VM descartável do GitHub Actions — ele reconfigura a máquina inteira" >&2
  exit 1
fi

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
ADMIN=$(id -un)
TOOLS="$RUNNER_TEMP/ci"
grupo() { echo "::group::$*"; }
fim() { echo "::endgroup::"; }

grupo "diagnóstico do runner"
id
ls -l /etc/apt/sources.list.d
sysctl kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || true
ss -tuln
fim

grupo "ambiente global igual ao de uma VPS"
# A imagem do runner grava dezenas de variáveis em /etc/environment (PATH com /home/runner,
# XDG_RUNTIME_DIR=/run/user/1001, XDG_CONFIG_HOME…), e o PAM injeta esse arquivo em TODA sessão,
# inclusive na sessão systemd do hermes — o Docker rootless dele tentava usar /run/user/1001.
# Numa VPS Ubuntu esse arquivo só tem o PATH; deixamos o runner igual (o original fica guardado).
sudo cp /etc/environment /etc/environment.runner
echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"' |
  sudo tee /etc/environment >/dev/null
fim

grupo "grupo do admin"
# No runner do GitHub, o grupo primário do usuário pode não ter o nome dele. Os scripts usam
# "$ADMIN:$ADMIN" (ex.: /opt/jarvis e /var/backups/jarvis), então o grupo precisa existir e conter o admin.
getent group "$ADMIN" >/dev/null || sudo groupadd "$ADMIN"
sudo usermod -aG "$ADMIN" "$ADMIN"
fim

grupo "ferramentas"
"$REPO/ci/instalar-ferramentas.sh" "$TOOLS" bats lynis
fim

grupo "repo em /opt/jarvis (admin: $ADMIN)"
sudo rm -rf /opt/jarvis
sudo cp -a "$REPO" /opt/jarvis
sudo chown -R "$ADMIN:$ADMIN" /opt/jarvis
sudo sed -i "s/^ADMIN_USER=.*/ADMIN_USER=\${ADMIN_USER:-$ADMIN}/" /opt/jarvis/provision/vars.sh
fim

JARVIS_CI=1
JARVIS_DASHBOARD_PASSWORD="ci-$(openssl rand -hex 16)"
export JARVIS_CI JARVIS_DASHBOARD_PASSWORD
rodar() { sudo --preserve-env=JARVIS_CI,JARVIS_DASHBOARD_PASSWORD "/opt/jarvis/provision/$1"; }

env_falso() {
  # .env com valores FALSOS (sem segredos no CI). O gateway não é iniciado.
  sudo -u hermes tee /var/lib/hermes/.hermes/.env >/dev/null <<'EOF'
# jarvis:env — valores falsos do CI
OPENAI_API_KEY=ci-falso
TELEGRAM_BOT_TOKEN=ci-falso
TELEGRAM_ALLOWED_USERS=1
TELEGRAM_HOME_CHANNEL=1
GITHUB_TOKEN=ci-falso
EOF
}

provisionar() {
  rodar 00-bootstrap.sh
  rodar 10-sistema.sh
  rodar 20-wireguard.sh
  rodar 30-dns-caddy.sh
  rodar 40-hermes.sh
  if ! sudo -u hermes grep -q '^OPENAI_API_KEY=.' /var/lib/hermes/.hermes/.env; then
    env_falso
    rodar 40-hermes.sh
  fi
  rodar 50-docker-rootless.sh
  rodar 60-backup.sh
  rodar 70-chatwoot.sh
}

grupo "provisionamento — 1ª vez"
provisionar
fim

grupo "provisionamento — 2ª vez (idempotência)"
provisionar
fim

grupo "dispositivo de teste na VPN"
sudo jarvis-peer add ci-teste >/dev/null
[[ -n $(sudo wg show wg0 peers) ]]
fim

grupo "auditoria"
# sudo -u: sessão nova, que já enxerga o grupo acrescentado acima.
sudo -u "$ADMIN" -H env PATH="$TOOLS/bin:$PATH" bats /opt/jarvis/tests/integracao
fim

grupo "Lynis"
lynis_dir=$(dirname "$(readlink -f "$TOOLS/bin/lynis")")
sudo chown -R root:root "$lynis_dir"   # o Lynis exige seus arquivos com dono root
(cd "$lynis_dir" && sudo ./lynis audit system --quick --no-colors --report-file /tmp/lynis-report.dat >/dev/null)
sudo install -m 644 /tmp/lynis-report.dat "$RUNNER_TEMP/lynis-report.dat"
indice=$(grep '^hardening_index=' "$RUNNER_TEMP/lynis-report.dat" | cut -d= -f2)
minimo=$(grep -vE '^[[:space:]]*(#|$)' /opt/jarvis/ci/lynis-minimo.txt)
echo "Lynis: índice de endurecimento $indice (mínimo exigido: $minimo)"
echo "### Lynis: índice de endurecimento **$indice** (mínimo $minimo)" >>"$GITHUB_STEP_SUMMARY"
fim
((indice >= minimo)) || { echo "Lynis: índice $indice abaixo do mínimo $minimo" >&2; exit 1; }
