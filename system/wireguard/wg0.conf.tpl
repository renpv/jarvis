# Gerado por provision/20-wireguard.sh (só se o arquivo não existir).
# Os dispositivos ([Peer]) são acrescentados por `sudo jarvis-peer add NOME`.
[Interface]
Address = @WG_SERVER_IP@/24
ListenPort = @WG_PORT@
PrivateKey = @WG_SERVER_PRIVKEY@
