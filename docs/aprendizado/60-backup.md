# 60 — Backup e restauração

Tarefa 16 do plano base. Script: `provision/60-backup.sh`. Ferramenta: `bin/jarvis-backup`.
Comandos do dia a dia e restauração em VPS nova: `docs/operacao.md`, seção 5.

## O que entra e o que não entra

| Entra | Não entra (e por quê) |
|---|---|
| `~/.hermes`: `config.yaml`, `SOUL.md`, `.env`, memórias, sessões, `state.db`, cron, skills, token do Google | `.hermes/logs` (descartável) |
| `~/apps` (código e dados dos apps publicados) | `.hermes/hermes-agent`, `installs`, `tools`, `cache`: o instalador do Hermes refaz (~3 GB) |
| `~/notas` (tarefas) | chaves do WireGuard (os dispositivos são adicionados de novo) |
| | `/etc/caddy/secrets.env` (o `30-dns-caddy.sh` pede a senha de novo) |
| | `/opt/jarvis` (vem do GitHub) |

Até 23/10 o backup levava também a instalação do Hermes e tinha ~950 MB **comprimido**. Sem ela,
cai para **1,5 MB** (#33). A restauração não perde nada com isso, porque os scripts 00→60
reinstalam o Hermes **antes** de extrair o backup.

## Por que o Hermes para durante a cópia

O `state.db` é um banco SQLite em uso. Copiar o arquivo enquanto o Hermes grava pode produzir uma
cópia corrompida (metade de uma transação). O `jarvis-backup` para o `hermes-gateway` e o
`hermes-dashboard`, copia e liga os dois de novo, mesmo se o `tar` falhar. Com o backup enxuto,
a parada dura menos de um segundo.

## Retenção

- Todo dia às 03:00 (`jarvis-backup.timer`), em `/var/backups/jarvis/` (dono root, grupo `renpv`, modo 640).
- Mantém **7 diários + 4 semanais**. O backup de domingo é o semanal.
- `jarvis backup` faz um na hora. O `jarvis update` também faz um antes de atualizar o Hermes.

## O teste de restauração real (critério 10, 23/10)

O backup automático das 03:00 foi extraído num diretório temporário e conferido:

| Verificação | Resultado |
|---|---|
| `tar -I zstd -xpf` | ok |
| donos e modos | preservados (`.env` hermes 600, `config.yaml` 640, `notas` 750) |
| logs | fora, como esperado |
| `PRAGMA integrity_check` em `state.db`, `kanban.db`, `projects.db`, `shared-state.db` | `ok` nos quatro |
| `.env`, `SOUL.md`, `notas` | iguais aos vivos |

O teste também mostrou que o Jarvis tinha editado a própria skill `publicar-app` (guia 40).

Para repetir o teste:

```bash
f=$(sudo sh -c 'ls -t /var/backups/jarvis/*.tar.zst | head -1')
t=$(sudo mktemp -d /root/restore-teste.XXXX)
sudo tar -C "$t" -I zstd -xpf "$f" && sudo ls -A "$t/.hermes"
sudo sh -c "for db in $t/.hermes/*.db; do echo \$db: \$(sqlite3 \$db 'PRAGMA integrity_check'); done"
sudo rm -rf "$t"
```

## Regra 3-2-1: onde estamos

A regra: **3** cópias, em **2** tipos de mídia, **1** fora do lugar.

| Cópia | Onde | Status |
|---|---|---|
| 1 | os dados vivos na VPS | ✅ |
| 2 | `/var/backups/jarvis` na VPS | ✅ (mesmo disco: protege contra erro, não contra perda da VPS) |
| 3 | `~/backups/jarvis` no computador, via `./bin/jarvis backup pull` (lembrete no Telegram todo domingo às 10:00) | ✅ |
| fora | uma cópia longe da VPS e de casa (ex.: disco externo ou nuvem, cifrada) | próximo passo opcional |

O backup contém o `.env` e o token do Google. A cópia no computador merece o mesmo cuidado que uma
senha: disco cifrado (BitLocker) e fora de pastas sincronizadas sem criptografia.
