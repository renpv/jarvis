# Jarvis

Assistente pessoal baseado no [Hermes Agent](https://github.com/NousResearch/hermes-agent),
rodando numa VPS própria. Conversa pelo Telegram e por um dashboard acessível só pela VPN WireGuard.

- Design: [docs/specs/2026-10-17-jarvis-base-design.md](docs/specs/2026-10-17-jarvis-base-design.md)
- Plano: [docs/plans/2026-10-17-jarvis-base.md](docs/plans/2026-10-17-jarvis-base.md)
- Operação do dia a dia: [docs/operacao.md](docs/operacao.md)
- Para aprender: [docs/aprendizado/](docs/aprendizado/) — comece por `00-como-o-hermes-funciona.md`

## Onde fica cada coisa

| | Caminho | Papel |
|---|---|---|
| Computador | `/home/renpv/dev/jarvis` | onde você edita |
| GitHub | `renpv/jarvis` (privado) | ponto de encontro e backup |
| VPS | `/opt/jarvis` | onde os scripts rodam (o Hermes não acessa) |
| VPS | `/var/lib/hermes/.hermes` | arquivos "vivos" do Hermes (não é repo) |

## Pastas

- `provision/` — scripts que preparam a VPS, em ordem (`00` a `60`). Idempotentes.
- `system/` — modelos de configuração do sistema (WireGuard, Caddy, systemd...).
- `hermes/` — a parte do Hermes que você controla: `config.yaml`, `SOUL.md`, `skills/jarvis/`.
- `bin/` — ferramentas: `jarvis` (apply/diff/import/status...), `jarvis-expose`, `jarvis-peer`, `jarvis-backup`.
- `tests/` — testes (`make test`).

## Fluxo de trabalho

`feat/<assunto>` → PR para `main` (portão 1) → PR `main` → `prod` (portão 2) → `jarvis deploy` na VPS.
Primeira vez num clone: `make ferramentas && make hooks`. Detalhes: [docs/aprendizado/80-ci-e-fluxo-git.md](docs/aprendizado/80-ci-e-fluxo-git.md).

## Segredos

Nenhum segredo entra no Git. O modelo está em [.env.example](.env.example); o `.env`
real existe só na VPS, em `/var/lib/hermes/.hermes/.env`.

## Testes

```bash
make ferramentas   # uma vez: ferramentas fixadas por checksum em .ci-bin/
make test          # lint + bats
make ci            # o portão 1 inteiro, igual ao GitHub
```
