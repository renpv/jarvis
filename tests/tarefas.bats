load helpers

@test "google_tasks.py: criar, listar, concluir, adiar e apagar (Google Tasks falso)" {
  run python3 -I "$REPO_ROOT/tests/google_tasks_test.py"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "skill tarefas usa o Google Tasks pelo script, e não mais o arquivo tarefas.md" {
  f="$REPO_ROOT/hermes/skills/jarvis/tarefas/SKILL.md"
  grep -q 'scripts/tarefas' "$f"
  ! grep -q 'notas/tarefas.md' "$f"
}
