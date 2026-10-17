# Operação do Jarvis

Comandos do dia a dia, manutenção e solução de problemas. Os comandos com `jarvis` rodam
**na VPS** como `renpv` (eles usam `sudo` quando precisam), exceto `jarvis backup pull`, que
roda **no computador**.

## 1. Dia a dia

| Para… | Comando |
|---|---|
| Ver se está tudo de pé | `jarvis status` |
| Ver o que o Hermes/dashboard mudou | `jarvis diff` |
| Trazer essas mudanças para o repo | `jarvis import` → `git diff` → `git commit` → `git push` |
| Aplicar o repo no Hermes | `jarvis apply` |
| Usar o CLI do Hermes como o usuário hermes | `jarvis hermes <comando>` (ex.: `jarvis hermes cron list`) |
| Conferir o `.env` | `jarvis check-env` |
| Logs do gateway | `journalctl -u hermes-gateway -n 100 --no-pager` |

## 2. Mudar a configuração (`config.yaml`, `SOUL.md`, skills)

1. No computador: edite em `~/dev/jarvis/hermes/`, faça commit e `git push`.
2. Na VPS:
   ```bash
   cd /opt/jarvis && git pull && jarvis apply
   ```
3. Se o `apply` recusar, o Hermes tem mudanças que não estão no repo: rode `jarvis diff` e decida
   entre `jarvis import` (manter) ou `jarvis apply --force` (descartar).

Mudanças nos scripts de `provision/` ou em `system/`: `git pull` e rode de novo o script do
assunto (ex.: `sudo provision/30-dns-caddy.sh`). Eles são idempotentes.

## 3. Novo dispositivo na VPN

```bash
sudo jarvis-peer add NOME     # ex.: tablet
sudo jarvis-peer list
```

- **Android:** app WireGuard → "+" → "Escanear código QR".
- **Windows:** `sudo cat /etc/wireguard/clients/NOME.conf` → app WireGuard → "Adicionar túnel" →
  "Adicionar túnel vazio" → colar → salvar.
- **Nunca cole essa config em um chat** (ela contém a chave privada do dispositivo).

Revogar um dispositivo: apague o bloco que começa com `# peer: NOME` em
`/etc/wireguard/wg0.conf` e rode `sudo systemctl restart wg-quick@wg0`.

## 4. Atualizar

- **Hermes:** `jarvis update` (faz backup, roda `hermes update`, reinicia e mostra o status).
- **Sistema:** as atualizações de segurança são automáticas. Uma vez por mês, as demais:
  ```bash
  sudo apt update && sudo apt full-upgrade
  ```
  Se aparecer `*** System restart required ***` ao entrar na VPS, rode `sudo reboot` num horário
  tranquilo.

## 5. Backup

- Automático todo dia às 03:00, em `/var/backups/jarvis/` (7 diários + 4 semanais).
- Agora: `jarvis backup`.
- Cópia para o computador (no WSL, com a VPN ligada no Windows):
  ```bash
  cd ~/dev/jarvis && ./bin/jarvis backup pull
  ```
  Se o SSH precisar de outra chave ou usuário: `VPS_SSH=renpv@10.8.0.1 ./bin/jarvis backup pull`.

### Restaurar em uma VPS nova

1. Siga as Tarefas 12–16 do plano (scripts `00` → `60`).
2. Pare o Hermes: `sudo systemctl stop hermes-gateway hermes-dashboard`
3. Envie o backup (do computador): `scp ~/backups/jarvis/ARQUIVO.tar.zst renpv@10.8.0.1:/tmp/`
4. Restaure:
   ```bash
   sudo tar -C /var/lib/hermes -I zstd -xpf /tmp/ARQUIVO.tar.zst
   sudo chown -R hermes:hermes /var/lib/hermes/.hermes /var/lib/hermes/apps /var/lib/hermes/notas
   jarvis diff
   sudo systemctl start hermes-gateway hermes-dashboard
   ```
5. Suba de novo cada app:
   ```bash
   sudo -u hermes -H env XDG_RUNTIME_DIR=/run/user/$(id -u hermes) \
     DOCKER_HOST=unix:///run/user/$(id -u hermes)/docker.sock \
     bash -c 'cd /var/lib/hermes/apps/APP && docker compose up -d'
   sudo jarvis-expose APP PORTA
   ```

**O que NÃO está no backup:** as chaves do WireGuard (os dispositivos são adicionados de novo),
`/etc/caddy/secrets.env` (o `30-dns-caddy.sh` pede a senha de novo) e o clone `/opt/jarvis`
(vem do GitHub).

## 6. Tokens com validade

| Token | Validade | Como renovar |
|---|---|---|
| GitHub (fine-grained) | 90 dias | gere outro com as mesmas permissões e troque `GITHUB_TOKEN` no `.env` |
| Google OAuth | sem prazo, se o app estiver "Em produção" | no modo "Teste" o token expira em 7 dias: publique o app (uso pessoal não exige verificação) |
| OpenAI | sem prazo | revogue e gere outra se vazar |

Trocar um valor no `.env`:
```bash
sudo nano /var/lib/hermes/.hermes/.env
jarvis check-env
sudo systemctl restart hermes-gateway hermes-dashboard
```

## 7. Problemas comuns

| Sintoma | O que fazer |
|---|---|
| `hermes.jarvis.lan` não abre no Windows | O túnel está ativo? `nslookup hermes.jarvis.lan 10.8.0.1` deve responder `10.8.0.1`. Se o Windows ignorar o DNS do túnel, acrescente `10.8.0.1 hermes.jarvis.lan` em `C:\Windows\System32\drivers\etc\hosts` (como administrador). |
| Não abre no Android | Configurações → Rede → **DNS privado**: use "Automático" ou "Desativado". Um provedor fixo ignora o DNS da VPN. |
| Gateway não sobe | `journalctl -u hermes-gateway -n 100 --no-pager` e `jarvis check-env`. |
| Aba Chat do dashboard não conecta | Abra o console do navegador (F12). Se houver erro de WebSocket/Origin, acrescente `header_up Origin http://127.0.0.1:9119` no `reverse_proxy` de `system/caddy/Caddyfile.tpl`, faça push e rode `sudo provision/30-dns-caddy.sh`. |
| `jarvis apply` recusou | `jarvis diff`, depois `jarvis import` (manter) ou `jarvis apply --force` (descartar). |
| `jarvis import` abortou com "segredo" | Algum arquivo do Hermes ganhou um token. Tire-o do arquivo (ele vai no `.env`) e rode de novo. |
| App publicado não abre | `ls /etc/caddy/apps.d/` mostra o app? A VPN está ligada? Peça ao Jarvis um diagnóstico (skill `monitorar-vps`). |
| Trancado fora do SSH | Use o console web do provedor e entre como `renpv` com a senha. Confira `/etc/ssh/sshd_config.d/00-jarvis.conf`. |
