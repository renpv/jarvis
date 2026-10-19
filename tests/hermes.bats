load helpers

@test "cada skill tem frontmatter com name igual ao nome da pasta e description" {
  for d in "$REPO_ROOT"/hermes/skills/jarvis/*/; do
    n=$(basename "$d")
    f="$d/SKILL.md"
    [ -f "$f" ] || { echo "sem SKILL.md: $n"; return 1; }
    [ "$(head -1 "$f")" = "---" ]
    grep -qx "name: $n" "$f" || { echo "name errado em $n"; return 1; }
    grep -qE '^description: .{10,}' "$f" || { echo "sem description em $n"; return 1; }
  done
}

@test "existem as três skills do Jarvis" {
  for n in publicar-app tarefas monitorar-vps; do
    [ -f "$REPO_ROOT/hermes/skills/jarvis/$n/SKILL.md" ]
  done
}

@test "publicar-app usa a mesma faixa de portas e domínio do vars.sh" {
  source "$REPO_ROOT/provision/vars.sh"
  f="$REPO_ROOT/hermes/skills/jarvis/publicar-app/SKILL.md"
  grep -q "$APP_PORT_MIN–$APP_PORT_MAX" "$f"
  grep -q "$DOMAIN" "$f"
}

@test "SOUL.md tem as regras de segredo e de confirmação" {
  f="$REPO_ROOT/hermes/SOUL.md"
  grep -qi "segredo" "$f"
  grep -q "jarvis-expose" "$f"
  grep -q "America/Fortaleza" "$f"
}
