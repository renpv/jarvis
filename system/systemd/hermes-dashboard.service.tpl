# Gerado por provision/40-hermes.sh. Escuta só em 127.0.0.1; o acesso é pelo Caddy, na VPN.
[Unit]
Description=Hermes Agent — dashboard web
After=network-online.target user@@HERMES_UID@.service
Wants=network-online.target user@@HERMES_UID@.service

[Service]
Type=simple
User=@HERMES_USER@
Group=@HERMES_USER@
WorkingDirectory=@HERMES_DIR@
Environment=HOME=@HERMES_DIR@
Environment=HERMES_HOME=@HERMES_DIR@/.hermes
Environment=XDG_RUNTIME_DIR=/run/user/@HERMES_UID@
Environment=DOCKER_HOST=unix:///run/user/@HERMES_UID@/docker.sock
Environment=PATH=@HERMES_DIR@/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=@HERMES_DIR@/.local/bin/hermes dashboard --host 127.0.0.1 --port @DASHBOARD_PORT@ --no-open
Restart=on-failure
RestartSec=10
# 78 = "outro processo já serve este host": não adianta reiniciar em loop.
RestartPreventExitStatus=78

[Install]
WantedBy=multi-user.target
