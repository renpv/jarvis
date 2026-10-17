#!/usr/bin/env bash
# 00-bootstrap — primeiro acesso à VPS recém-instalada. Roda como ROOT, uma única vez.
#   1. atualiza o sistema
#   2. cria o administrador (ADMIN_USER) com sudo e a mesma chave SSH do root
#   3. cria a chave SSH do admin para o GitHub e clona o repo em /opt/jarvis
# Uso (do seu computador):
#   scp -r provision root@IP_DA_VPS:/root/
#   ssh root@IP_DA_VPS 'bash /root/provision/00-bootstrap.sh'
set -euo pipefail
# shellcheck source=provision/lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"
require_root

log "atualizando o sistema (pode demorar alguns minutos)"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get -y -q full-upgrade
apt_install git curl ca-certificates

if id "$ADMIN_USER" &>/dev/null; then
  ok "usuário $ADMIN_USER já existe"
else
  log "criando usuário $ADMIN_USER"
  adduser --disabled-password --gecos "" "$ADMIN_USER"
fi
usermod -aG sudo "$ADMIN_USER"

if [[ $(passwd -S "$ADMIN_USER" | awk '{print $2}') != P ]]; then
  log "defina a senha de $ADMIN_USER (usada pelo sudo; o login SSH continua só por chave)"
  passwd "$ADMIN_USER"
fi

home=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
[[ -s /root/.ssh/authorized_keys ]] || die "root não tem chave SSH. No seu computador: ssh-copy-id root@IP_DA_VPS"
install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "$home/.ssh"
if [[ ! -s $home/.ssh/authorized_keys ]]; then
  install -m 600 -o "$ADMIN_USER" -g "$ADMIN_USER" /root/.ssh/authorized_keys "$home/.ssh/authorized_keys"
  ok "chave SSH copiada para $ADMIN_USER"
fi

# Cópia das variáveis para as ferramentas de root (jarvis-peer, jarvis-backup).
install -D -m 644 "$PROVISION_DIR/vars.sh" /etc/jarvis/vars.sh

key="$home/.ssh/id_ed25519_github"
if [[ ! -f $key ]]; then
  runuser -u "$ADMIN_USER" -- ssh-keygen -q -t ed25519 -N "" -C "$ADMIN_USER@$(hostname)-jarvis" -f "$key"
fi

if [[ ! -d $JARVIS_DIR/.git ]]; then
  echo
  echo "Adicione esta chave como Deploy Key, marcando 'Allow write access', em:"
  echo "  https://github.com/$GITHUB_SLUG/settings/keys/new"
  echo
  cat "$key.pub"
  echo
  read -rp "Pressione Enter depois de salvar a chave no GitHub... "
  install -d -m 750 -o "$ADMIN_USER" -g "$ADMIN_USER" "$JARVIS_DIR"
  runuser -u "$ADMIN_USER" -- env \
    GIT_SSH_COMMAND="ssh -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
    git clone "$GITHUB_REPO" "$JARVIS_DIR"
  runuser -u "$ADMIN_USER" -- git -C "$JARVIS_DIR" config core.sshCommand "ssh -i $key -o IdentitiesOnly=yes"
fi
chmod 750 "$JARVIS_DIR"
ln -sfn "$JARVIS_DIR/bin/jarvis" /usr/local/bin/jarvis

ok "bootstrap concluído"
cat <<EOM

PRÓXIMOS PASSOS — não feche esta sessão de root ainda:
  1. Em OUTRO terminal:  ssh $ADMIN_USER@IP_DA_VPS   e depois   sudo -v
  2. Se os dois funcionarem, nesse novo terminal:
       cd $JARVIS_DIR && sudo provision/10-sistema.sh
EOM
