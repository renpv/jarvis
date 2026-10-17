# Gerado por provision/10-sistema.sh. No sshd, o primeiro valor lido vence: por isso o prefixo 00.
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowUsers @ADMIN_USER@
