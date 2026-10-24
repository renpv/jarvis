load helpers

@test "google_tasks.py: criar, listar, concluir, adiar e apagar (Google Tasks falso)" {
  run python3 -I -B "$REPO_ROOT/tests/google_tasks_test.py"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "skill tarefas usa o Google Tasks pelo script, e não mais o arquivo tarefas.md" {
  f="$REPO_ROOT/hermes/skills/jarvis/tarefas/SKILL.md"
  grep -q 'scripts/tarefas' "$f"
  ! grep -q 'notas/tarefas.md' "$f"
}

@test "scripts/tarefas roda o Python com -B (sem __pycache__ nas skills, que apareceria no jarvis diff)" {
  grep -q 'exec "$py" -B ' "$REPO_ROOT/hermes/skills/jarvis/tarefas/scripts/tarefas"
}

@test "nenhum bytecode do Python versionado" {
  run git -C "$REPO_ROOT" ls-files '*.pyc' '*/__pycache__/*'
  [ -z "$output" ] || { echo "$output"; return 1; }
}
