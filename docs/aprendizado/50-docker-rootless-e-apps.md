# 50 — Docker rootless e apps publicados

Tarefa 15 do plano base. Script: `provision/50-docker-rootless.sh`. Ferramenta: `bin/jarvis-expose`.

## Por que rootless

O Docker comum roda como root, e quem está no grupo `docker` controla esse daemon. Com ele, dá para
montar `/` num container e editar qualquer arquivo da máquina: **o grupo `docker` equivale a root**.
Dar isso ao `hermes` anularia todo o resto do isolamento.

No modo **rootless**, cada usuário tem o próprio daemon, que roda **como ele**. O root de dentro do
container é o `hermes` do lado de fora. O pior que um app consegue fazer é o que o `hermes` já pode.
O Docker de root fica instalado (os pacotes são os mesmos), mas **parado e desabilitado**.

## As peças

| Peça | O que faz |
|---|---|
| `/etc/subuid`, `/etc/subgid` (`hermes:300000:65536`) | faixa de IDs que o `hermes` pode usar dentro dos containers. O root do container vira o `hermes`, e os outros usuários do container viram 300000+ |
| `loginctl enable-linger hermes` | mantém a sessão systemd do `hermes` (e o `/run/user/UID`) ativa mesmo sem login. Sem isso, o daemon morreria |
| `systemctl --user enable --now docker` | o daemon do `hermes`, como serviço de usuário |
| `DOCKER_HOST=unix:///run/user/UID/docker.sock` | onde o comando `docker` encontra esse daemon (definido nos serviços do Hermes) |
| perfil AppArmor do `rootlesskit` | o Ubuntu 24.04 restringe *user namespaces* sem privilégio; o perfil libera só o `rootlesskit` |
| `slirp4netns` | a rede dos containers sem root (instalado explicitamente: nem todo ambiente instala os "Recommends") |

Para usar o Docker do `hermes` à mão:

```bash
sudo -u hermes -H env XDG_RUNTIME_DIR=/run/user/$(id -u hermes) \
  DOCKER_HOST=unix:///run/user/$(id -u hermes)/docker.sock docker ps
```

## Publicar um app: `jarvis-expose`

O Caddy roda como root e serve a VPN inteira. Se o `hermes` pudesse escrever a configuração dele,
poderia apontar `hermes.jarvis.lan` para outro lugar ou abrir uma porta pública. Por isso o
`hermes` **nunca escreve no Caddy**. Ele tem sudo para dois comandos e mais nada:

```
hermes ALL=(root) NOPASSWD: /usr/local/sbin/jarvis-expose, /usr/local/sbin/jarvis-unexpose
```

O fluxo (skill `publicar-app`):

1. O Jarvis cria `~/apps/<nome>/compose.yaml`, com a porta presa em `127.0.0.1:<81xx>`.
2. `docker compose up -d --build` e `curl` local para testar.
3. Com o "sim" do Renato: `sudo jarvis-expose <nome> <porta>`. O script:
   - valida o nome (2 a 31 caracteres: minúsculas, números e hífen, começando por letra; reservados: `hermes`, `www`, `dns`, `vpn`, `admin`) e a porta (8100–8199);
   - gera `/etc/caddy/apps.d/<nome>.caddy` a partir de um modelo fixo;
   - roda `caddy validate`. Se falhar, desfaz e mantém a configuração anterior;
   - recarrega o Caddy.
4. O app abre em `http://<nome>.jarvis.lan`, só com a VPN ligada.

`sudo jarvis-unexpose <nome>` remove a publicação. O `jarvis-unexpose` é um link para o mesmo script.

## Resultados (Tarefa 15)

- **Docker rootless:** `docker run hello-world` como `hermes` funciona, e o Docker de root está
  parado. A auditoria do CI (`tests/integracao/auditoria.bats`) confere as duas coisas a cada lançamento.
- **Isolamento:** o `hermes` não tem sudo além do expose/unexpose e não lê `/opt/jarvis`.
  O `jarvis-expose ../x 8100` é recusado.
- **App de exemplo (critério 7):** o Jarvis publicou `exemplo` em `127.0.0.1:8100`, e
  `http://exemplo.jarvis.lan` abriu pela VPN. Ele pediu confirmação antes do `jarvis-expose`.
  - No Windows do minipc, o nome precisou de uma linha no `hosts`, como o `hermes.jarvis.lan`.
    O motivo é a regra NRPT de outra VPN (guia 30). **Cada app novo precisa de uma linha igual.**
  - O terminal do Hermes barrou o `docker compose up` por parecer um processo longo. O Jarvis o
    rodou em segundo plano e registrou a lição na própria skill.
- **Pendente (opcional):** reiniciar a VPS e conferir que o app volta sozinho (`restart: unless-stopped` + linger).
