# 20 — VPN WireGuard

Tarefa 13 do plano base. Script: `provision/20-wireguard.sh`. Ferramenta: `jarvis-peer`.

## A ideia

O WireGuard cria uma rede privada (`10.8.0.0/24`) entre a VPS e os seus dispositivos. Tudo que é
web do Jarvis (dashboard, apps) só existe **dentro** dessa rede: na internet, a VPS expõe só o SSH
(22/tcp) e o WireGuard (51820/udp).

| Peça | Valor |
|---|---|
| Interface na VPS | `wg0`, IP `10.8.0.1` |
| Porta | `51820/udp` |
| Dispositivos | um IP cada, a partir de `10.8.0.2` (nunca o do servidor) |
| DNS | `10.8.0.1` (o dnsmasq da VPS — guia 30) |

## Chaves

Cada lado tem um **par de chaves**: a privada nunca sai do aparelho; a pública vai para o outro
lado. Além disso, cada dispositivo tem uma **PresharedKey** (chave simétrica extra, uma camada a
mais). A chave privada do servidor fica em `/etc/wireguard/server.key` (modo 600).

## A configuração de um dispositivo

```ini
[Interface]
PrivateKey = …            # do dispositivo — por isso a config nunca vai para chat
Address = 10.8.0.2/32
DNS = 10.8.0.1

[Peer]
PublicKey = …             # do servidor
PresharedKey = …
Endpoint = IP_PÚBLICO_DA_VPS:51820
AllowedIPs = 10.8.0.0/24  # só o tráfego da VPN passa pelo túnel
PersistentKeepalive = 25  # mantém o túnel vivo atrás de roteador/NAT
```

**`AllowedIPs = 10.8.0.0/24`** (e não `0.0.0.0/0`): só o que é para a VPS passa pelo túnel; a sua
navegação comum continua saindo pela sua internet.

## Adicionar, listar, revogar

```bash
sudo jarvis-peer add minipc          # cria chaves, registra, mostra QR code
sudo cat /etc/wireguard/clients/minipc.conf
sudo jarvis-peer list                # nome, IP, último contato
```

Revogar: apague o bloco `# peer: NOME` em `/etc/wireguard/wg0.conf` e
`sudo systemctl restart wg-quick@wg0`.

## O que aconteceu na prática

- O primeiro dispositivo foi o **minipc** (Windows com WSL): app WireGuard no **Windows**, túnel
  `vps-hostinger`, IP `10.8.0.2`. O WSL usa a rede do Windows e enxerga a VPN sem configurar nada.
- Teste: `ping 10.8.0.1` respondeu no PowerShell e no WSL (~61 ms); `jarvis-peer list` mostrou o
  último contato.

## Conferir à mão

```bash
sudo wg show wg0                 # peers, último handshake, bytes trafegados
systemctl status wg-quick@wg0
sudo ufw status | grep 51820
```
