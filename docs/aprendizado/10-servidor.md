# 10 — O servidor base (bootstrap e endurecimento)

Tarefa 12 do plano base. Scripts: `provision/00-bootstrap.sh` e `provision/10-sistema.sh`.
Executada em 2026-10-19/22 na VPS `179.197.74.162` (Ubuntu 24.04, 2 vCPU, 8 GB).

## O que cada script faz

### `00-bootstrap.sh` — roda como **root**, uma vez

| Passo | Por quê |
|---|---|
| `apt full-upgrade` | começar com o sistema atualizado (trouxe kernel novo → *System restart required*) |
| cria `renpv` e põe no grupo `sudo` | nunca trabalhar como root no dia a dia; o sudo pede **senha** (uma segunda barreira além da chave SSH) |
| copia `authorized_keys` do root para `renpv` | a mesma chave do seu computador passa a entrar como `renpv` |
| `/etc/jarvis/vars.sh` | cópia das variáveis para as ferramentas de root (`jarvis-peer`, `jarvis-backup`) |
| chave `id_ed25519_github` + **deploy key** | a VPS clona o repo privado sem usar a sua conta inteira do GitHub; a chave só vale para `renpv/jarvis` |
| `git clone -b prod` em `/opt/jarvis` (modo 750) | a VPS acompanha o branch `prod`; o usuário `hermes` não consegue ler o repo |

### `10-sistema.sh` — roda como **`renpv` com sudo**

Antes de tudo, o **preflight** confere variáveis, Ubuntu 24.04, que é o `renpv` via sudo e que ele
tem `authorized_keys` (senão endurecer o SSH trancaria você para fora).

| Peça | Configuração |
|---|---|
| Fuso | `America/Fortaleza` |
| Atualizações | `unattended-upgrades` aplica só as de **segurança**, sozinho |
| Firewall (ufw) | entrada **bloqueada**, exceto SSH; saída liberada |
| fail2ban | bane por 1 h quem errar o login SSH 5 vezes em 10 min (lê o journal) |
| SSH | sem root, sem senha, sem teclado interativo, só o usuário `renpv` |

## Lição 1 — "o primeiro valor lido vence" no sshd

Na sua VPS, o provedor deixou estes arquivos:

```
/etc/ssh/sshd_config:12:Include /etc/ssh/sshd_config.d/*.conf
/etc/ssh/sshd_config:130:PermitRootLogin yes
/etc/ssh/sshd_config.d/00-jarvis.conf:2:PermitRootLogin no
/etc/ssh/sshd_config.d/50-cloud-init.conf:1:PasswordAuthentication yes
/etc/ssh/sshd_config.d/60-cloudimg-settings.conf:1:PasswordAuthentication no
```

O `sshd` usa o **primeiro** valor que encontra para cada opção. O `Include` está na linha 12, então
os arquivos de `sshd_config.d/` são lidos antes da linha 130 — e, dentro da pasta, em ordem
alfabética. Por isso o nosso arquivo se chama **`00-`**: ele vence o `PermitRootLogin yes` do
provedor e o `PasswordAuthentication yes` do cloud-init. Para ver o valor **efetivo**:

```bash
sudo sshd -T | grep -iE '^(permitrootlogin|passwordauthentication|kbdinteractive)'
```

## Lição 2 — `cmd | grep -q` com `pipefail` mente

Na primeira execução, o `10-sistema.sh` parou com `ERRO PermitRootLogin não está 'no'` — com a
configuração **certa**. A verificação era `sshd -T | grep -qx 'permitrootlogin no'`. O `grep -q`
sai assim que acha a linha; o `sshd` ainda estava escrevendo e levou SIGPIPE; com `set -o pipefail`,
o pipeline inteiro conta como falha. Correção (PR renpv/jarvis#14): capturar a saída antes —
`cfg=$(sshd -T); grep -qx '...' <<<"$cfg"`. Um teste agora impede esse padrão em todos os scripts.

## Conferir tudo à mão

```bash
sudo sshd -T | grep -iE '^(permitrootlogin|passwordauthentication)'   # no / no
sudo ufw status verbose                                               # active; 22/tcp ALLOW
sudo fail2ban-client status sshd                                      # jail ativa, IPs banidos
systemctl status unattended-upgrades --no-pager | head -3             # active
timedatectl | grep 'Time zone'                                        # America/Fortaleza
```

E do seu computador:

```bash
ssh -i ~/.ssh/id_renpv root@179.197.74.162 true    # Permission denied (publickey) — esperado
ssh -i ~/.ssh/id_renpv renpv@179.197.74.162        # entra
```

## Resultado real

- `10-sistema.sh` → `ok sistema pronto`
- `ssh root@…` → `Permission denied (publickey)`, saída 255
- `jarvis check` → tudo ✅ exceto o `.env` do Hermes (esperado até a Tarefa 14)
- `jarvis deploy` → `nada novo em prod (a1232dd)`

## Se algo der errado

- **Trancado fora do SSH:** use o console web do provedor e entre como `renpv` com a senha do sudo;
  confira `/etc/ssh/sshd_config.d/00-jarvis.conf` e `sudo sshd -t`.
- **Seu IP foi banido pelo fail2ban** (errou a chave várias vezes): pelo console,
  `sudo fail2ban-client set sshd unbanip SEU_IP`.
