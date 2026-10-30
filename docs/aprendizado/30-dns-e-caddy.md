# 30 — DNS interno e Caddy

Tarefa 13 do plano base. Script: `provision/30-dns-caddy.sh`.

## DNS interno (dnsmasq)

O dnsmasq escuta **só** em `10.8.0.1` (dentro da VPN) e:
- responde qualquer `*.jarvis.lan` com `10.8.0.1`;
- encaminha os outros nomes para `1.1.1.1` e `9.9.9.9`.

Os apps WireGuard não fazem "DNS dividido" por domínio: com o túnel ligado, o dispositivo pergunta
**tudo** ao `10.8.0.1` — por isso ele precisa encaminhar o resto.

```bash
dig +short @10.8.0.1 hermes.jarvis.lan   # 10.8.0.1
dig +short @10.8.0.1 github.com          # IPs públicos
```

## Caddy

Proxy reverso. Até 30/10 escutava só em `10.8.0.1:80`. Desde o Chatwoot (guia 90), cada site declara o próprio `bind`: os da tabela abaixo ficam em `10.8.0.1`, e só `atendimento.renpv.com.br` escuta no IP público (80/443, com HTTPS automático).

| Endereço | Para onde vai | Proteção |
|---|---|---|
| `http://hermes.jarvis.lan` | dashboard do Hermes (`127.0.0.1:9119`) | usuário e senha (`basic_auth`) + checagem de Origin |
| `http://<app>.jarvis.lan` | app publicado pelo Jarvis (`127.0.0.1:81xx`) | só a VPN |

- HTTP sem TLS é aceitável aqui: o WireGuard já cifra o tráfego.
- A senha do dashboard fica como **hash** em `/etc/caddy/secrets.env` (fora do Git).
- A API de administração do Caddy fica num socket que só o usuário `caddy` acessa — se ficasse em
  `localhost:2019`, qualquer usuário local (inclusive o `hermes`) poderia reconfigurá-lo.

Validar à mão:

```bash
sudo bash -c 'set -a; . /etc/caddy/secrets.env; caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile'
```

## O que aconteceu na prática

### 1. Outra VPN no minipc "sequestrava" o DNS

No Windows, `hermes.jarvis.lan` não resolvia — nem perguntando direto ao `10.8.0.1`. Causa: outra
VPN ativa no minipc ("Conexão Local 2", métrica 1) instalou uma regra de DNS do Windows (**NRPT**)
para o namespace `"."` — *todos os nomes* — apontando para o DNS dela, e bloqueia DNS para outros
servidores. O WSL pergunta ao resolvedor do Windows (`nameserver 10.255.255.254`), então falhava junto.

Solução (no PowerShell como administrador):

```powershell
Add-Content -Path "$env:SystemRoot\System32\drivers\etc\hosts" -Value "`r`n10.8.0.1  hermes.jarvis.lan   # Jarvis (VPN WireGuard)"; ipconfig /flushdns
```

O `hosts` vale antes de qualquer DNS, então funciona com a outra VPN ligada. **Cada app publicado
no futuro (`<app>.jarvis.lan`) precisa de uma linha igual.** Com a outra VPN desligada, o DNS da
VPN funciona sozinho.

### 2. A aba Chat do dashboard não conectava

Log do Hermes (`/var/lib/hermes/.hermes/logs/`):

```
pty refused: origin_mismatch origin=http://hermes.jarvis.lan bound=127.0.0.1
```

A aba Chat usa um **WebSocket**, e o dashboard só aceita WebSocket cuja *Origin* (o site que o
navegador declara) aponte para o endereço em que ele escuta. É uma proteção contra
*cross-site WebSocket hijacking*: sem ela, uma página maliciosa aberta no seu navegador poderia
usar a sua sessão para controlar o Hermes.

Solução (PR renpv/jarvis#25): o **Caddy** faz a checagem — Origin diferente de
`http://hermes.jarvis.lan` recebe **403**; a certa é reescrita para `127.0.0.1:9119`. Testado com
um Caddy real:

| Requisição | Resultado |
|---|---|
| sem senha | 401 |
| com senha, Origin certa | passa |
| com senha, `Origin: http://evil.example` | 403 |
| com senha, `Origin: http://app.jarvis.lan` | 403 (um app do próprio Jarvis também não controla o dashboard) |

## Conferir à mão

```bash
systemctl is-active caddy dnsmasq
sudo ss -tulpn | grep -vE '127\.0\.0\.|\[::1\]|10\.8\.0\.1'   # só :22 e :51820 (e DHCP)
curl -s -o /dev/null -w '%{http_code}\n' --resolve hermes.jarvis.lan:80:10.8.0.1 http://hermes.jarvis.lan/   # 401
```
