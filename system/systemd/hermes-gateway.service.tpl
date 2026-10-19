# Gerado por provision/40-hermes.sh.
# Sem NoNewPrivileges: o hermes precisa do sudo restrito (jarvis-expose).
[Unit]
Description=Hermes Agent — gateway (Telegram, cron, aprovações)
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
ExecStart=@HERMES_DIR@/.local/bin/hermes gateway run
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
