# DNS da VPN (gerado por provision/30-dns-caddy.sh).
# Responde *.@DOMAIN@ com o IP da VPS na VPN e encaminha os outros nomes para a internet.
listen-address=@WG_SERVER_IP@
bind-interfaces
except-interface=lo
no-resolv
server=1.1.1.1
server=9.9.9.9
domain-needed
bogus-priv
address=/@DOMAIN@/@WG_SERVER_IP@
cache-size=1000
