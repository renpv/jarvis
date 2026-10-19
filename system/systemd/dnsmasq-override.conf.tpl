# O dnsmasq escuta no IP da VPN, então só pode subir depois do WireGuard.
[Unit]
After=wg-quick@@WG_IF@.service
Requires=wg-quick@@WG_IF@.service
