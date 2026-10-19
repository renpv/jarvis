# Gerado por provision/50-docker-rootless.sh.
# O usuário @HERMES_USER@ só pode rodar estes dois comandos como root, sem senha.
@HERMES_USER@ ALL=(root) NOPASSWD: /usr/local/sbin/jarvis-expose, /usr/local/sbin/jarvis-unexpose
