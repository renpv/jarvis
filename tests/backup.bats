load helpers

setup() {
  make_sandbox
  mkdir -p "$SANDBOX/src/.hermes/logs" "$SANDBOX/src/apps/site" "$SANDBOX/src/notas"
  echo mem > "$SANDBOX/src/.hermes/MEMORY.md"
  echo log > "$SANDBOX/src/.hermes/logs/gateway.log"
  echo app > "$SANDBOX/src/apps/site/compose.yaml"
  echo t > "$SANDBOX/src/notas/tarefas.md"
  cat > "$SANDBOX/ctl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$SANDBOX/ctl.log"
EOF
  chmod +x "$SANDBOX/ctl"
  export JARVIS_VARS="$REPO_ROOT/provision/vars.sh"
  export SRC_DIR="$SANDBOX/src" BACKUP_DIR="$SANDBOX/bk" BACKUP_GROUP="$(id -gn)" SERVICE_CTL="$SANDBOX/ctl"
  BACKUP="$REPO_ROOT/bin/jarvis-backup"
}

@test "gera backup diário com estado, apps e notas, sem logs" {
  export JARVIS_DATE=2026-10-17
  run "$BACKUP"
  [ "$status" -eq 0 ]
  f="$SANDBOX/bk/jarvis-daily-2026-10-17.tar.zst"
  [ -f "$f" ]
  [ "$(stat -c %a "$f")" = 640 ]
  list=$(tar -I zstd -tf "$f")
  [[ $list == *".hermes/MEMORY.md"* ]]
  [[ $list == *"apps/site/compose.yaml"* ]]
  [[ $list == *"notas/tarefas.md"* ]]
  [[ $list != *"gateway.log"* ]]
}

@test "deixa de fora o que o instalador do Hermes refaz (código, ambientes, ferramentas, cache)" {
  for d in hermes-agent installs tools cache; do
    mkdir -p "$SANDBOX/src/.hermes/$d/sub"
    echo x > "$SANDBOX/src/.hermes/$d/sub/arquivo"
  done
  mkdir -p "$SANDBOX/src/apps/site/cache" "$SANDBOX/src/.hermes/skills/tools"
  echo app > "$SANDBOX/src/apps/site/cache/dado"
  echo s > "$SANDBOX/src/.hermes/skills/tools/SKILL.md"
  export JARVIS_DATE=2026-10-17
  run "$BACKUP"
  [ "$status" -eq 0 ]
  list=$(tar -I zstd -tf "$SANDBOX/bk/jarvis-daily-2026-10-17.tar.zst")
  for d in hermes-agent installs tools cache; do
    [[ $list != *".hermes/$d/"* ]] || { echo ".hermes/$d entrou no backup"; return 1; }
  done
  # o filtro vale só para esses diretórios no topo de .hermes
  [[ $list == *"apps/site/cache/dado"* ]]
  [[ $list == *".hermes/skills/tools/SKILL.md"* ]]
  [[ $list == *".hermes/MEMORY.md"* ]]
}

@test "domingo gera backup semanal" {
  export JARVIS_DATE=2026-10-18
  run "$BACKUP"
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX/bk/jarvis-weekly-2026-10-18.tar.zst" ]
}

@test "para e religa os serviços do Hermes" {
  export JARVIS_DATE=2026-10-17
  "$BACKUP"
  grep -qx "stop hermes-gateway hermes-dashboard" "$SANDBOX/ctl.log"
  grep -qx "start hermes-gateway hermes-dashboard" "$SANDBOX/ctl.log"
}

@test "mantém só os 7 diários mais recentes" {
  mkdir -p "$SANDBOX/bk"
  for d in 01 02 03 04 05 06 07 08 09; do touch "$SANDBOX/bk/jarvis-daily-2026-10-$d.tar.zst"; done
  touch "$SANDBOX/bk/jarvis-weekly-2026-10-04.tar.zst"
  export JARVIS_DATE=2026-10-17
  "$BACKUP"
  [ "$(ls "$SANDBOX/bk"/jarvis-daily-*.tar.zst | wc -l)" -eq 7 ]
  [ ! -e "$SANDBOX/bk/jarvis-daily-2026-10-03.tar.zst" ]
  [ -e "$SANDBOX/bk/jarvis-daily-2026-10-04.tar.zst" ]
  [ -e "$SANDBOX/bk/jarvis-daily-2026-10-17.tar.zst" ]
  [ -e "$SANDBOX/bk/jarvis-weekly-2026-10-04.tar.zst" ]
}

@test "religa os serviços mesmo se o tar falhar" {
  export JARVIS_DATE=2026-10-17 SRC_DIR="$SANDBOX/nao-existe"
  mkdir -p "$SRC_DIR/.hermes"
  chmod 000 "$SRC_DIR/.hermes"
  run "$BACKUP"
  chmod 755 "$SRC_DIR/.hermes"
  [ "$status" -ne 0 ]
  grep -qx "start hermes-gateway hermes-dashboard" "$SANDBOX/ctl.log"
}

@test "aceita 'arquivo mudou durante a leitura' (tar sai com 1) de um app rodando" {
  mkdir -p "$SANDBOX/fakebin"
  cat > "$SANDBOX/fakebin/tar" <<'EOT'
#!/usr/bin/env bash
# finge o tar: cria o arquivo de saída e sai com 1 (file changed as we read it)
while [[ $# -gt 0 ]]; do if [[ $1 == -cf ]]; then : > "$2"; fi; shift; done
echo "tar: apps/db: file changed as we read it" >&2
exit 1
EOT
  chmod +x "$SANDBOX/fakebin/tar"
  export PATH="$SANDBOX/fakebin:$PATH" JARVIS_DATE=2026-10-17
  run "$BACKUP"
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX/bk/jarvis-daily-2026-10-17.tar.zst" ]
}
