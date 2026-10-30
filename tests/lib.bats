load helpers

setup() {
  make_sandbox
  source "$REPO_ROOT/provision/lib.sh"
}

@test "render substitui placeholders, inclusive valores com & e /" {
  printf 'a=@FOO@ b=@BAR@\n' > "$SANDBOX/t.tpl"
  FOO=1
  BAR='x&y/z'
  run render "$SANDBOX/t.tpl" FOO BAR
  [ "$status" -eq 0 ]
  [ "$output" = "a=1 b=x&y/z" ]
}

@test "render aceita placeholder colado em @ (ex.: wg-quick@@WG_IF@)" {
  printf 'After=wg-quick@@WG_IF@.service\n' > "$SANDBOX/t.tpl"
  WG_IF=wg0
  run render "$SANDBOX/t.tpl" WG_IF
  [ "$status" -eq 0 ]
  [ "$output" = "After=wg-quick@wg0.service" ]
}

@test "render falha quando a variável não está definida" {
  printf '@NAO_EXISTE@\n' > "$SANDBOX/t.tpl"
  unset NAO_EXISTE
  run render "$SANDBOX/t.tpl" NAO_EXISTE
  [ "$status" -ne 0 ]
  [[ "$output" == *"NAO_EXISTE"* ]]
}

@test "render falha quando sobra placeholder não listado" {
  printf '@FOO@ @OUTRO@\n' > "$SANDBOX/t.tpl"
  FOO=1
  run render "$SANDBOX/t.tpl" FOO
  [ "$status" -ne 0 ]
  [[ "$output" == *"@OUTRO@"* ]]
}

@test "install_file instala, marca mudança e não mexe na segunda vez" {
  echo conteudo > "$SANDBOX/src"
  JARVIS_CHANGED=0
  install_file "$SANDBOX/src" "$SANDBOX/sub/dst" 640
  [ "$JARVIS_CHANGED" -eq 1 ]
  [ "$(stat -c %a "$SANDBOX/sub/dst")" = 640 ]
  touch -d '2000-01-01' "$SANDBOX/sub/dst"
  JARVIS_CHANGED=0
  install_file "$SANDBOX/src" "$SANDBOX/sub/dst" 640
  [ "$JARVIS_CHANGED" -eq 0 ]
  [ "$(stat -c %Y "$SANDBOX/sub/dst")" = "$(date -d '2000-01-01' +%s)" ]
}

@test "install_file atualiza quando o conteúdo muda" {
  echo v1 > "$SANDBOX/src"
  install_file "$SANDBOX/src" "$SANDBOX/dst" 644
  echo v2 > "$SANDBOX/src"
  JARVIS_CHANGED=0
  install_file "$SANDBOX/src" "$SANDBOX/dst" 644
  [ "$JARVIS_CHANGED" -eq 1 ]
  [ "$(cat "$SANDBOX/dst")" = v2 ]
}

@test "install_file falha se o arquivo de origem não existe" {
  run install_file "$SANDBOX/nao-existe" "$SANDBOX/dst" 644
  [ "$status" -ne 0 ]
}

@test "vars.sh permite sobrescrever valores pelo ambiente" {
  run bash -c "HERMES_USER=outro; source '$REPO_ROOT/provision/vars.sh'; echo \$HERMES_USER \$WG_SERVER_IP"
  [ "$output" = "outro 10.8.0.1" ]
}

@test "apt_install espera o lock do dpkg (VPS recém-criada roda unattended-upgrades)" {
  mkdir -p "$SANDBOX/bin"
  printf '#!/usr/bin/env bash\necho "$@" > "%s/apt-args"\n' "$SANDBOX" > "$SANDBOX/bin/apt-get"
  chmod +x "$SANDBOX/bin/apt-get"
  PATH="$SANDBOX/bin:$PATH" apt_install pacote
  grep -q 'DPkg::Lock::Timeout=' "$SANDBOX/apt-args"
  grep -q 'pacote' "$SANDBOX/apt-args"
}

@test "apt_get desiste de espelho travado e tenta de novo (um download preso já custou 14 min no CI)" {
  mkdir -p "$SANDBOX/bin"
  printf '#!/usr/bin/env bash\necho "$@" > "%s/apt-args"\n' "$SANDBOX" > "$SANDBOX/bin/apt-get"
  chmod +x "$SANDBOX/bin/apt-get"
  PATH="$SANDBOX/bin:$PATH" apt_get update
  grep -q 'Acquire::http::Timeout=' "$SANDBOX/apt-args"
  grep -q 'Acquire::https::Timeout=' "$SANDBOX/apt-args"
  grep -q 'Acquire::Retries=' "$SANDBOX/apt-args"
}

@test "as_hermes roda com ambiente limpo (nada do admin vaza, ex.: XDG_CONFIG_HOME)" {
  mkdir -p "$SANDBOX/bin"
  # sudo falso: descarta "-u USUÁRIO" e executa o resto, para observar o ambiente entregue
  printf '#!/usr/bin/env bash\nshift 2\nexec "$@"\n' > "$SANDBOX/bin/sudo"
  chmod +x "$SANDBOX/bin/sudo"
  HERMES_USER=$(id -un) HERMES_DIR="$SANDBOX/hermes"
  export XDG_CONFIG_HOME=/home/outro/.config SEGREDO_DO_ADMIN=x
  PATH="$SANDBOX/bin:$PATH" run as_hermes /usr/bin/env
  [ "$status" -eq 0 ]
  [[ "$output" != *"XDG_CONFIG_HOME"* ]]
  [[ "$output" != *"SEGREDO_DO_ADMIN"* ]]
  [[ "$output" == *"HOME=$SANDBOX/hermes"* ]]
  [[ "$output" == *"HERMES_HOME=$SANDBOX/hermes/.hermes"* ]]
}

@test "as_usuario roda como outro usuário de serviço, com ambiente limpo e a home dele" {
  mkdir -p "$SANDBOX/bin"
  printf '#!/usr/bin/env bash\nshift 2\nexec "$@"\n' > "$SANDBOX/bin/sudo"
  chmod +x "$SANDBOX/bin/sudo"
  export SEGREDO_DO_ADMIN=x
  PATH="$SANDBOX/bin:$PATH" run as_usuario "$(id -un)" "$SANDBOX/chatwoot" /usr/bin/env
  [ "$status" -eq 0 ]
  [[ "$output" != *"SEGREDO_DO_ADMIN"* ]]
  [[ "$output" == *"HOME=$SANDBOX/chatwoot"* ]]
  [[ "$output" != *"HERMES_HOME"* ]]
}
