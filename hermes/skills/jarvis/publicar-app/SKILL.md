---
name: publicar-app
description: Publica um app web (container Docker) na VPS, acessível só pela VPN em http://<nome>.jarvis.lan
version: 1.0.0
author: Renato e Jarvis
platforms: [linux]
metadata:
  hermes:
    tags: [deploy, docker, caddy, jarvis]
---

# Publicar app na VPS

## Quando usar
Quando Renato pedir para publicar, hospedar, "colocar no ar" ou deixar acessível um app ou site.

## Regras
- Apps são de uso pessoal: acessíveis **só pela VPN WireGuard**, em `http://<nome>.jarvis.lan`.
- A porta do host é sempre `127.0.0.1:<porta>`, com porta na faixa **8100–8199**. Nunca `0.0.0.0`.
- Nome: 2 a 31 caracteres, letras minúsculas, números e hífen, começando com letra.
  Reservados: `hermes`, `www`, `dns`, `vpn`, `admin`.
- Peça confirmação a Renato antes do passo 5.

## Procedimento
1. Veja as portas já usadas e escolha uma livre:
   `grep -h reverse_proxy /etc/caddy/apps.d/*.caddy 2>/dev/null`
2. Crie `/var/lib/hermes/apps/<nome>/` com o código e um `compose.yaml`:
   ```yaml
   services:
     app:
       build: .                 # ou: image: <imagem>
       restart: unless-stopped
       ports:
         - "127.0.0.1:<porta>:<porta-interna>"
   ```
3. Suba: `cd /var/lib/hermes/apps/<nome> && docker compose up -d --build`
   - Se o terminal bloquear esse comando dizendo que parece iniciar um servidor/processo longo, rode o mesmo comando com `background=true` e `notify=true`, depois aguarde com `process_manage action=wait`; o `docker compose up -d` deve encerrar sozinho e deixar o container em segundo plano.
4. Teste: `curl -fsS http://127.0.0.1:<porta>/ | head`
5. Com o "sim" de Renato: `sudo jarvis-expose <nome> <porta>`
6. Verifique depois do expose: `test -f /etc/caddy/apps.d/<nome>.caddy` e `curl -fsS http://127.0.0.1:<porta>/`.
7. Responda com `http://<nome>.jarvis.lan` e lembre que só abre com a VPN ligada.

## Remover
1. `sudo jarvis-unexpose <nome>`
2. `cd /var/lib/hermes/apps/<nome> && docker compose down`
3. Pergunte antes de apagar a pasta.

## Problemas comuns
- `porta ... já usada por ...`: escolha outra porta da faixa.
- `o Caddy rejeitou a configuração`: nada mudou; confira nome e porta.
- `Cannot connect to the Docker daemon`: `systemctl --user status docker`.
- App sumiu depois de reiniciar a VPS: faltou `restart: unless-stopped` no compose.

## Verificação
`curl -fsS http://127.0.0.1:<porta>/` responde e `/etc/caddy/apps.d/<nome>.caddy` existe.
