---
name: monitorar-vps
description: Verifica a saúde da VPS (serviços, disco, memória, logs de erro, containers) e explica o que encontrou
version: 1.0.0
author: Renato e Jarvis
platforms: [linux]
metadata:
  hermes:
    tags: [devops, monitoramento, jarvis]
---

# Monitorar a VPS

## Quando usar
Quando Renato perguntar se está tudo bem com o servidor, pedir um diagnóstico, ou quando um
app/serviço parecer fora do ar. Também no resumo matinal (só a linha de alerta).

## Comandos (todos sem sudo)
| O quê | Comando |
|---|---|
| Serviços com falha | `systemctl --failed --no-legend` |
| Estado dos principais | `systemctl is-active hermes-gateway hermes-dashboard caddy dnsmasq wg-quick@wg0` |
| Erros do boot atual | `journalctl -p err -b --no-pager -n 50` |
| Log de um serviço | `journalctl -u <serviço> --no-pager -n 100` |
| Disco | `df -h / /var/lib/hermes` |
| Memória | `free -h` |
| Carga | `uptime` |
| Containers (rootless) | `docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'` |
| Apps publicados | `ls /etc/caddy/apps.d/` |
| Atualizações pendentes | `apt list --upgradable` (conte as linhas) |

## Procedimento
1. Rode os comandos relevantes à pergunta (não todos, se a pergunta for específica).
2. Resuma: ✅ o que está ok, ⚠️ o que merece atenção, ❌ o que está quebrado.
3. Para cada problema, diga a causa provável e o próximo passo. Se exigir root, diga o comando
   exato que Renato deve rodar (você não tem sudo).

## Limites
- Disco acima de 85% ou memória livre abaixo de 10% são alertas.
- Não reinicie serviços do sistema (não tem permissão); containers seus você pode reiniciar com
  `docker compose restart` na pasta do app, avisando Renato.
