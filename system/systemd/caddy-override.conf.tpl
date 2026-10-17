# O Caddy escuta no IP da VPN, então só pode subir depois do WireGuard.
[Unit]
After=wg-quick@@WG_IF@.service
Requires=wg-quick@@WG_IF@.service

[Service]
# Usuário e hash da senha do dashboard (não versionados).
EnvironmentFile=/etc/caddy/secrets.env
# /run/caddy só do usuário caddy: guarda o socket da API admin.
RuntimeDirectory=caddy
RuntimeDirectoryMode=0700
