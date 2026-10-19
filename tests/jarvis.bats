load helpers

setup() {
  make_sandbox
  export JARVIS_REPO="$SANDBOX/repo"
  export HERMES_HOME="$SANDBOX/live/.hermes"
  export JARVIS_STATE="$SANDBOX/state"
  export HERMES_USER="$(id -un)" HERMES_GROUP="$(id -gn)" ADMIN_USER=admin-teste
  export SUDO="" HSUDO="" SYSTEMCTL=":"
  mkdir -p "$JARVIS_REPO/hermes/skills/jarvis/exemplo" "$HERMES_HOME" "$JARVIS_STATE"
  cp -r "$REPO_ROOT/provision" "$JARVIS_REPO/"
  git -C "$JARVIS_REPO" init -q
  echo "model: a" > "$JARVIS_REPO/hermes/config.yaml"
  echo "# alma" > "$JARVIS_REPO/hermes/SOUL.md"
  echo "skill v1" > "$JARVIS_REPO/hermes/skills/jarvis/exemplo/SKILL.md"
  JARVIS="$REPO_ROOT/bin/jarvis"
}

@test "apply instala config, SOUL e skills gerenciadas no Hermes" {
  run "$JARVIS" apply
  [ "$status" -eq 0 ]
  cmp "$JARVIS_REPO/hermes/config.yaml" "$HERMES_HOME/config.yaml"
  cmp "$JARVIS_REPO/hermes/SOUL.md" "$HERMES_HOME/SOUL.md"
  cmp "$JARVIS_REPO/hermes/skills/jarvis/exemplo/SKILL.md" "$HERMES_HOME/skills/jarvis/exemplo/SKILL.md"
}

@test "apply não mexe em skills do Hermes fora de skills/jarvis" {
  mkdir -p "$HERMES_HOME/skills/github/x"
  echo nativa > "$HERMES_HOME/skills/github/x/SKILL.md"
  "$JARVIS" apply
  [ "$(cat "$HERMES_HOME/skills/github/x/SKILL.md")" = nativa ]
}

@test "apply recusa sobrescrever config existente que nunca foi importada" {
  echo "model: padrao" > "$HERMES_HOME/config.yaml"
  run "$JARVIS" apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"jarvis import"* ]]
  [ "$(cat "$HERMES_HOME/config.yaml")" = "model: padrao" ]
}

@test "apply recusa quando o Hermes mudou algo depois do último apply" {
  "$JARVIS" apply
  echo "model: mudado-pelo-dashboard" > "$HERMES_HOME/config.yaml"
  echo "model: b" > "$JARVIS_REPO/hermes/config.yaml"
  run "$JARVIS" apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"jarvis diff"* ]]
  [ "$(cat "$HERMES_HOME/config.yaml")" = "model: mudado-pelo-dashboard" ]
}

@test "apply --force descarta as mudanças do Hermes" {
  "$JARVIS" apply
  echo "model: mudado" > "$HERMES_HOME/config.yaml"
  echo "model: b" > "$JARVIS_REPO/hermes/config.yaml"
  run "$JARVIS" apply --force
  [ "$status" -eq 0 ]
  [ "$(cat "$HERMES_HOME/config.yaml")" = "model: b" ]
}

@test "apply remove do Hermes a skill gerenciada que saiu do repo" {
  "$JARVIS" apply
  rm -r "$JARVIS_REPO/hermes/skills/jarvis/exemplo"
  mkdir -p "$JARVIS_REPO/hermes/skills/jarvis/outra"
  echo outra > "$JARVIS_REPO/hermes/skills/jarvis/outra/SKILL.md"
  run "$JARVIS" apply
  [ "$status" -eq 0 ]
  [ ! -e "$HERMES_HOME/skills/jarvis/exemplo" ]
  [ -f "$HERMES_HOME/skills/jarvis/outra/SKILL.md" ]
}

@test "apply falha com mensagem clara se o repo não tem config.yaml" {
  rm "$JARVIS_REPO/hermes/config.yaml"
  run "$JARVIS" apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"hermes/config.yaml"* ]]
}

@test "diff sai com 0 quando igual e com 1 mostrando a mudança" {
  "$JARVIS" apply
  run "$JARVIS" diff
  [ "$status" -eq 0 ]
  echo "model: z" > "$HERMES_HOME/config.yaml"
  run "$JARVIS" diff
  [ "$status" -eq 1 ]
  [[ "$output" == *"+model: z"* ]]
}

@test "import traz as mudanças do Hermes para o repo e libera o próximo apply" {
  "$JARVIS" apply
  echo "model: z" > "$HERMES_HOME/config.yaml"
  mkdir -p "$HERMES_HOME/skills/jarvis/nova"
  echo nova > "$HERMES_HOME/skills/jarvis/nova/SKILL.md"
  run "$JARVIS" import
  [ "$status" -eq 0 ]
  [ "$(cat "$JARVIS_REPO/hermes/config.yaml")" = "model: z" ]
  [ -f "$JARVIS_REPO/hermes/skills/jarvis/nova/SKILL.md" ]
  run "$JARVIS" apply
  [ "$status" -eq 0 ]
}

@test "import mantém no repo um arquivo que não existe no Hermes" {
  "$JARVIS" apply
  rm "$HERMES_HOME/SOUL.md"
  run "$JARVIS" import
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOUL.md"* ]]
  [ "$(cat "$JARVIS_REPO/hermes/SOUL.md")" = "# alma" ]
}

@test "import aborta ao encontrar segredo e não altera o repo" {
  "$JARVIS" apply
  # token falso montado em tempo de execução, para não deixar um padrão de token no Git
  fake="sk-proj-$(printf 'a%.0s' {1..30})"
  printf 'model: a\napi_key: %s\n' "$fake" > "$HERMES_HOME/config.yaml"
  run "$JARVIS" import
  [ "$status" -ne 0 ]
  [[ "$output" == *"segredo"* ]]
  [ "$(cat "$JARVIS_REPO/hermes/config.yaml")" = "model: a" ]
}

@test "check-env falha quando o .env não existe" {
  run "$JARVIS" check-env
  [ "$status" -ne 0 ]
  [[ "$output" == *".env"* ]]
}

@test "check-env lista as variáveis vazias ou ausentes" {
  printf 'OPENAI_API_KEY=x\nTELEGRAM_BOT_TOKEN=\n' > "$HERMES_HOME/.env"
  chmod 600 "$HERMES_HOME/.env"
  run "$JARVIS" check-env
  [ "$status" -ne 0 ]
  [[ "$output" == *"TELEGRAM_BOT_TOKEN"* ]]
  [[ "$output" == *"GITHUB_TOKEN"* ]]
  [[ "$output" != *"OPENAI_API_KEY"* ]]
}

@test "check-env passa com tudo preenchido" {
  printf '%s=x\n' OPENAI_API_KEY TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USERS TELEGRAM_HOME_CHANNEL GITHUB_TOKEN > "$HERMES_HOME/.env"
  chmod 600 "$HERMES_HOME/.env"
  run "$JARVIS" check-env
  [ "$status" -eq 0 ]
}

@test "sem subcomando mostra a ajuda e sai com 2" {
  run "$JARVIS"
  [ "$status" -eq 2 ]
  [[ "$output" == *"jarvis apply"* ]]
}

@test "apply recusa link simbólico plantado no Hermes e não toca o alvo" {
  "$JARVIS" apply
  mkdir -p "$SANDBOX/alvo" && echo importante > "$SANDBOX/alvo/arquivo"
  modo_antes=$(stat -c %a "$SANDBOX/alvo")
  rm -rf "$HERMES_HOME/skills"
  ln -s "$SANDBOX/alvo" "$HERMES_HOME/skills"
  run "$JARVIS" import
  [ "$status" -ne 0 ]
  run "$JARVIS" apply --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"link simbólico"* ]]
  [ "$(cat "$SANDBOX/alvo/arquivo")" = importante ]
  [ "$(stat -c %a "$SANDBOX/alvo")" = "$modo_antes" ]
}

@test "import recusa config.yaml que é link para outro arquivo" {
  "$JARVIS" apply
  echo "conteudo-sensivel" > "$SANDBOX/segredo"
  rm "$HERMES_HOME/config.yaml"
  ln -s "$SANDBOX/segredo" "$HERMES_HOME/config.yaml"
  run "$JARVIS" import
  [ "$status" -ne 0 ]
  [[ "$output" == *"link simbólico"* ]]
  [ "$(cat "$JARVIS_REPO/hermes/config.yaml")" = "model: a" ]
}

@test "diff recusa link simbólico dentro de skills/jarvis" {
  "$JARVIS" apply
  ln -s /dev/zero "$HERMES_HOME/skills/jarvis/exemplo/zero"
  run timeout 10 "$JARVIS" diff
  [ "$status" -ne 0 ]
  [ "$status" -ne 124 ]
  [[ "$output" == *"link simbólico"* ]]
}

@test "import aborta com chave de nome sensível ou chave privada PEM" {
  "$JARVIS" apply
  printf 'model: a\npassword: hunter2hunter2\n' > "$HERMES_HOME/config.yaml"
  run "$JARVIS" import
  [ "$status" -ne 0 ]
  [[ "$output" == *"segredo"* ]]
  printf 'model: a\n' > "$HERMES_HOME/config.yaml"
  printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n' > "$HERMES_HOME/skills/jarvis/exemplo/SKILL.md"
  run "$JARVIS" import
  [ "$status" -ne 0 ]
  [ "$(cat "$JARVIS_REPO/hermes/skills/jarvis/exemplo/SKILL.md")" = "skill v1" ]
}

@test "import aceita referência a variável de ambiente e chaves comuns" {
  "$JARVIS" apply
  printf 'model:\n  api_key: ${OPENAI_API_KEY}\n  key_env: OPENAI_API_KEY\nmax_tokens: 4096\n' > "$HERMES_HOME/config.yaml"
  run "$JARVIS" import
  [ "$status" -eq 0 ]
}

@test "apply/import/diff param no preflight com vars.sh inválido" {
  for c in apply import diff; do
    WG_PORT=99999 run "$JARVIS" $c
    [ "$status" -ne 0 ] || { echo "$c passou"; return 1; }
    [[ "$output" == *"WG_PORT"* ]]
  done
  [ ! -e "$HERMES_HOME/config.yaml" ]
}
