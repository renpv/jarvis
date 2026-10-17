# Jarvis — assistente pessoal com Hermes Agent em VPS

- **Data:** 2026-10-17
- **Status:** em revisão
- **Escopo:** etapas 1 a 5 (base, interface web, organização pessoal, assistente técnico, publicação de apps)

## 1. Objetivo

Construir um assistente pessoal ("Jarvis") baseado no [Hermes Agent](https://github.com/NousResearch/hermes-agent) (Nous Research), hospedado em uma VPS própria, acessível pelo celular (Telegram) e pelo computador (dashboard web).

O objetivo principal é **aprender**: entender como o Hermes funciona e manter uma configuração organizada, versionada e fácil de manter, e não só ter algo pronto funcionando.

**Critério de sucesso:** o dono entende as peças do Hermes (gateway, `config.yaml`, `SOUL.md`, memória, skills, cron, aprovações) a ponto de configurá-las sozinho, e todos os critérios de aceite da seção 10 passam.

### 1.1 Funcionalidades

| Área | O que o Jarvis faz |
|---|---|
| Conversa | Chat pelo Telegram (celular) e pela aba Chat do dashboard (computador) |
| Organização pessoal | Lembretes, agenda (Google Calendar), lista de tarefas, rotinas agendadas |
| Assistente técnico | Rodar comandos na VPS, monitorar serviços, ajudar em código, operar no GitHub |
| Publicação | Criar aplicações e publicá-las na própria VPS, acessíveis só ao dono |

### 1.2 Fora do escopo (deste projeto)

- Integração com WhatsApp e Instagram (DMs, posts, métricas). Será um projeto separado.
- Open WebUI ou outra interface de chat além do dashboard. Pode ser adicionada depois (`45-open-webui.sh`).
- Domínio próprio e apps públicos na internet.
- Agenda/tarefas auto-hospedadas (CalDAV/Radicale).

## 2. Decisões e justificativas

| # | Decisão | Alternativas descartadas | Por quê |
|---|---|---|---|
| D1 | Ubuntu 24.04 LTS, **instalação limpa** | Atualizar o 22.04 existente | Sem resíduos, reproduzível, suporte até 2029 |
| D2 | **WireGuard** + Caddy + dnsmasq (`*.jarvis.lan`) | Tailscale, Headscale, NetBird, túnel SSH, IP público + sslip.io | 100% open source, mínimo de peças, ótimo para aprender; nada web exposto à internet; não exige domínio |
| D3 | **Só o dashboard do Hermes** como interface web | Dashboard + Open WebUI | Reúne chat e configuração; nenhum serviço extra |
| D4 | Hermes como usuário de sistema `hermes`, **sem sudo geral**, terminal `local`, aprovação manual, apps em **Docker rootless** | Terminal em Docker (não enxerga o host); rodar como admin com sudo (risco total) | Atende monitorar/publicar sem que um erro ou prompt injection comprometa a VPS |
| D5 | Repositório Git + scripts bash idempotentes + comando `jarvis` (`apply`/`diff`/`import`) | Ansible; runbook manual; links simbólicos | Comandos visíveis (aprendizado); o Hermes não pode escrever no repo; links quebrariam com escrita atômica |
| D6 | Repo na VPS em `/opt/jarvis`, dono = admin, modo 750 | `/home/<user>/...`, `/var/lib/hermes/jarvis` | Se o Hermes pudesse alterar scripts rodados com sudo, escalaria para root |
| D7 | **Google Calendar** via skill `google-workspace`, só escopo Calendar | Radicale (CalDAV); só Hermes | Agenda já usada no Android; skill pronta |
| D8 | Tarefas em arquivo Markdown gerido pelo Hermes | Google Tasks | A skill não cobre Tasks; simples e trocável |
| D9 | Modelo: OpenAI (`openai-api`); modelo exato escolhido com `hermes model` na instalação | Fixar nome na spec | A lista de modelos muda; escolher na hora com o que a chave oferece |
| D10 | Fuso `America/Fortaleza`; idioma português | — | Preferência do dono |

## 3. Arquitetura

```
     Celular (Android)              Computador
   ┌──────────────────┐        ┌──────────────────┐
   │ Telegram         │        │ Navegador        │
   │ WireGuard app    │        │ WireGuard        │
   └───┬──────────┬───┘        └────────┬─────────┘
       │          │ túnel VPN (UDP)     │
       │          └──────────┬──────────┘
       │ internet            │
       ▼                     ▼
 servidores do     ┌─────────────────── VPS (Ubuntu 24.04) ───────────────────┐
 Telegram ◄────────┤ ufw: público só UDP WireGuard + SSH                      │
 (polling: o       │                                                          │
  Hermes busca     │ wg0 (10.8.0.1) ── dnsmasq: *.jarvis.lan → 10.8.0.1       │
  as mensagens)    │                └─ Caddy (escuta só em 10.8.0.1):         │
                   │                     hermes.jarvis.lan → dashboard :9119  │
                   │                     <app>.jarvis.lan  → 127.0.0.1:81xx   │
                   │                                                          │
                   │ usuário `hermes` (sem sudo geral):                       │
                   │   hermes-gateway.service   ── Telegram, cron, aprovações │
                   │   hermes-dashboard.service ── 127.0.0.1:9119             │
                   │   Docker rootless          ── apps publicados            │
                   │                                                          │
                   │ /opt/jarvis (repo, dono admin) ──jarvis apply──►         │
                   │                       /var/lib/hermes/.hermes            │
                   └──────────────────────────────────────────────────────────┘
                          │ saída HTTPS
                          ▼
                   OpenAI · GitHub · Google Calendar · Telegram
```

- **Rede VPN:** `10.8.0.0/24`; servidor `10.8.0.1`, celular `10.8.0.2`, computador `10.8.0.3`. Os clientes usam `AllowedIPs = 10.8.0.0/24` (só o tráfego da VPN passa pelo túnel; o resto da navegação segue normal) e `DNS = 10.8.0.1`. Como os apps WireGuard não fazem DNS dividido por domínio, o dnsmasq responde `*.jarvis.lan` e **encaminha os demais nomes** para resolvedores públicos.
- **Computador:** o cliente WireGuard roda no **Windows** (app oficial), não dentro do WSL. O navegador usa a VPN, e o WSL herda a conectividade.
- **Interfaces web:** HTTP simples dentro do túnel (o WireGuard já cifra). O Caddy só faz bind em `10.8.0.1`.
- **Dashboard:** protegido também por `basic_auth` no Caddy, porque guarda chaves de API.

## 4. Os quatro lugares dos arquivos

| | Caminho | Dono | Papel |
|---|---|---|---|
| ① Computador (WSL) | `/home/renpv/dev/jarvis` | renpv | Onde o dono edita, estuda e faz commit |
| ② GitHub | `renpv/jarvis` (privado) | — | Ponto de encontro, backup, histórico |
| ③ VPS, clone | `/opt/jarvis` (modo 750) | admin (`renpv`) | Onde os scripts rodam; o Hermes **não** lê |
| ④ VPS, arquivos vivos | `/var/lib/hermes/.hermes` | hermes | Não é repo: config em uso, memórias, sessões, cron |

**Fluxos:**
- **Mudança do dono:** edita em ① → push → `git pull` em ③ → `jarvis apply` (③ → ④, reinicia serviços).
- **Mudança do Hermes/dashboard:** acontece em ④ → `jarvis diff` (④ vs ③) → `jarvis import` (④ → ③) → commit/push em ③ → `git pull` em ①.
- O `.env` nunca passa por ①, ② ou ③: existe só em ④, com modo 600.

### 4.1 Layout da VPS

```
/opt/jarvis/                 clone do repo (admin, 750)
/usr/local/bin/jarvis        → /opt/jarvis/bin/jarvis
/usr/local/sbin/jarvis-expose, jarvis-unexpose   (root, 755; liberados ao hermes via sudoers)
/var/lib/hermes/             home do usuário de sistema hermes
├── .hermes/                 estado vivo do Hermes (+ .env, 600)
├── workspace/               clones dos projetos em que ele trabalha
└── apps/<nome>/compose.yaml apps publicados
/etc/wireguard/wg0.conf
/etc/caddy/Caddyfile         importa /etc/caddy/apps.d/*.caddy
/etc/caddy/apps.d/           escrito apenas por jarvis-expose (root)
/etc/dnsmasq.d/jarvis.conf
/etc/sudoers.d/hermes
/var/backups/jarvis/         backups (root, 600)
```

## 5. Estrutura do repositório

```
jarvis/
├── README.md                  visão geral e por onde começar
├── .gitignore                 bloqueia .env, chaves, estado
├── .env.example               todas as variáveis, comentadas, sem valores
├── docs/
│   ├── specs/                 specs de design
│   ├── aprendizado/           um guia por conceito/script (o "porquê")
│   └── operacao.md            runbook: atualizar, backup, restaurar, problemas
├── provision/                 rodados NA VPS, em ordem
│   ├── lib.sh                 funções comuns (log, checagens, idempotência)
│   ├── 00-bootstrap.sh        (root) cria admin, chave SSH, desliga root/senha no SSH
│   ├── 10-sistema.sh          unattended-upgrades, fuso, ufw, fail2ban
│   ├── 20-wireguard.sh        wg0 + gera peer por dispositivo (QR code)
│   ├── 30-dns-caddy.sh        dnsmasq + Caddy (bind só na VPN) + basic_auth
│   ├── 40-hermes.sh           usuário hermes, instalação, serviços systemd
│   ├── 50-docker-rootless.sh  Docker rootless do hermes, jarvis-expose, sudoers
│   └── 60-backup.sh           timer de backup diário
├── system/                    arquivos-modelo copiados pelos scripts
│   ├── wireguard/  caddy/  dnsmasq/  systemd/  sudoers/
├── hermes/                    parte declarativa do Hermes (→ ④)
│   ├── config.yaml
│   ├── SOUL.md
│   └── skills/                skills próprias (ex.: publicar-app)
└── bin/
    ├── jarvis                 apply · diff · import · status · update · backup
    ├── jarvis-expose
    └── jarvis-unexpose
```

**Regras dos scripts:** `set -euo pipefail`; idempotentes (verificam antes de agir); terminam conferindo o próprio resultado; numerados de 10 em 10. Cada script tem um guia correspondente em `docs/aprendizado/`.

## 6. Configuração do Hermes

### 6.1 Modelo
- Provedor `openai-api`, chave em `OPENAI_API_KEY`.
- Um modelo forte para o agente principal e um mais barato para tarefas auxiliares (compressão, títulos). A escolha é feita com `hermes model` e registrada no `config.yaml`.
- **Pré-requisito:** limite mensal de gasto configurado no painel da OpenAI antes de ligar o gateway.

### 6.2 Identidade (`SOUL.md`)
Em português, com o nome Jarvis. Conteúdo: quem é o dono, o fuso America/Fortaleza, o tom das respostas e as regras de conduta:
- confirmar antes de publicar apps ou fazer push;
- nunca pedir, aceitar nem repetir segredos no chat (orientar a editar o `.env`);
- explicar o que fez e por quê (o dono está aprendendo).

### 6.3 Segurança da execução (`config.yaml`)
```yaml
approvals:
  mode: manual
  timeout: 300            # sem resposta = negado
  deny:
    - "git push --force*"
    - "*curl*|*sh*"
    - "*wget*|*sh*"
    - "dd if=* of=/dev/*"
    - "rm -rf /*"
    - "*sudoers*"
security:
  redact_secrets: true
checkpoints:
  enabled: true
terminal:
  backend: local
```
As aprovações chegam no Telegram com botões Aprovar/Negar.

### 6.4 Permissões do usuário `hermes` no sistema
- Grupo `systemd-journal`: lê logs para monitorar serviços.
- `sudo` permitido **apenas** para `/usr/local/sbin/jarvis-expose` e `/usr/local/sbin/jarvis-unexpose`.
- Sem acesso a `/opt/jarvis`.
- Docker rootless próprio, sem acesso ao socket Docker de root.

### 6.5 Integrações
| Integração | Como | Restrições |
|---|---|---|
| Telegram | Bot do @BotFather; gateway por polling | `TELEGRAM_ALLOWED_USERS` = só o ID numérico do dono; `TELEGRAM_HOME_CHANNEL` = chat privado do dono |
| GitHub | Skills de GitHub nativas + `gh` CLI; `GITHUB_TOKEN` fine-grained | Só os repositórios escolhidos (o `jarvis` não entra); permissões: contents, pull requests, issues; commits como "Jarvis" |
| Google Calendar | Skill `google-workspace`; projeto Google Cloud + OAuth "Desktop app" | Só a API Calendar habilitada; o token fica no arquivo da skill em ④ |
| Tarefas | Arquivo Markdown em ④ gerido pelo Hermes | Entra no backup |
| Cron | `hermes cron`, entrega no Telegram | Rotina inicial: resumo matinal às 07:00 (agenda do dia + tarefas pendentes); lembrete semanal de `jarvis backup pull` |

### 6.6 Variáveis do `.env`
`OPENAI_API_KEY`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, `TELEGRAM_HOME_CHANNEL`, `GITHUB_TOKEN`. O `.env.example` documenta cada uma: onde obter, formato e permissões mínimas. Fora do `.env`: a senha do `basic_auth` do dashboard (hash no Caddyfile, gerado pelo script e nunca commitado), as chaves WireGuard (em `/etc/wireguard`, 600) e as credenciais do Google (geradas pela skill).

## 7. Publicação de apps

1. O Hermes cria o app em `/var/lib/hermes/apps/<nome>/` com um `compose.yaml` que publica só em `127.0.0.1:<porta>`, com a porta na faixa 8100–8199.
2. Sobe o app com o Docker rootless.
3. **Pede a confirmação do dono** (regra do `SOUL.md`).
4. Executa `sudo jarvis-expose <nome> <porta>`, que:
   - valida o nome (`^[a-z][a-z0-9-]{1,30}$`, sem colidir com `hermes`) e a porta (8100–8199);
   - gera `/etc/caddy/apps.d/<nome>.caddy` a partir de um modelo fixo (`http://<nome>.jarvis.lan` com bind em `10.8.0.1` → `reverse_proxy 127.0.0.1:<porta>`);
   - valida com `caddy validate` e recarrega. Se falhar, remove o arquivo novo e mantém a configuração anterior.
5. `jarvis-unexpose <nome>` remove o arquivo e recarrega.

A skill `hermes/skills/publicar-app/` documenta esse procedimento para o Hermes.

## 8. Operação

- **Backup:** timer systemd diário às 03:00 gera um `.tar.zst` de `/var/lib/hermes/.hermes` e `apps/`. Retenção de 7 diários e 4 semanais em `/var/backups/jarvis/` (root, 600). Cópia externa com `jarvis backup pull`, executado no computador pela VPN.
- **Restauração:** documentada em `docs/operacao.md` (VPS nova → scripts → restaurar backup) e testada ao menos uma vez.
- **Atualizações:** o sistema recebe só as atualizações de segurança automáticas (`unattended-upgrades`). O Hermes atualiza manualmente com `jarvis update` (backup → `hermes update` → reinício → status).
- **Falhas:** os scripts param no primeiro erro com mensagem clara e podem ser rodados de novo. Os serviços usam `Restart=on-failure`. `jarvis status` mostra serviços, WireGuard, portas públicas e o último backup.

## 9. Riscos conhecidos

| Risco | Mitigação |
|---|---|
| Prompt injection via conteúdo lido (web, issues, e-mails) | Usuário sem sudo, aprovações manuais, lista `deny`, repo `jarvis` fora do alcance, token GitHub restrito |
| Gasto descontrolado na OpenAI | Limite mensal no painel; modelo barato nas tarefas auxiliares |
| Perda da VPS | Backup diário + cópia no computador + restauração testada |
| Perda de acesso SSH após endurecimento | `00-bootstrap.sh` só desliga root/senha depois de testar o login com o novo usuário por chave; console do provedor como plano B |
| Mudança de comportamento em atualizações do Hermes | Atualização manual com backup prévio |

## 10. Critérios de aceite

1. Pelo Telegram, o Jarvis responde ao dono. Mensagens de outra conta são ignoradas.
2. Com o WireGuard ativo (celular e PC), `http://hermes.jarvis.lan` abre o dashboard após o `basic_auth`. Sem a VPN, nada responde.
3. `ss -tulpn` mostra apenas o SSH e a porta UDP do WireGuard na interface pública.
4. Um comando perigoso pede aprovação no Telegram e, sem resposta, é negado. Um comando da lista `deny` é bloqueado mesmo com aprovação.
5. O usuário `hermes` não consegue: usar `sudo` para algo além de `jarvis-expose`/`jarvis-unexpose`, ler `/opt/jarvis`, nem fazer push no repo `jarvis`.
6. O Jarvis cria um evento no Google Calendar, que aparece no Android.
7. O Jarvis publica um app de exemplo, acessível em `http://exemplo.jarvis.lan`.
8. O Jarvis abre um PR em um repositório de teste no GitHub.
9. O resumo matinal chega no Telegram no horário.
10. Um backup é restaurado com sucesso em um diretório de teste.
11. `jarvis diff` mostra uma mudança feita pelo dashboard, e `jarvis import` a traz para o repo.

## 11. Pendências para a instalação

- Nome do modelo OpenAI (decidido com `hermes model`).
- Porta UDP do WireGuard (padrão 51820; pode ser trocada).
- Nome do usuário admin na VPS (proposto: `renpv`).
