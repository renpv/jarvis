load helpers

setup() {
  make_sandbox
  mkdir -p "$SANDBOX/src/foo-1.0" "$SANDBOX/files"
  printf '#!/bin/sh\necho foo-ok\n' > "$SANDBOX/src/foo-1.0/foo"
  chmod +x "$SANDBOX/src/foo-1.0/foo"
  tar -C "$SANDBOX/src" -czf "$SANDBOX/files/foo-1.0.tar.gz" foo-1.0
  sha=$(sha256sum "$SANDBOX/files/foo-1.0.tar.gz" | cut -d' ' -f1)
  printf '# teste\nfoo 1.0 https://github.com/x/foo/foo-1.0.tar.gz %s foo-1.0/foo\n' "$sha" > "$SANDBOX/lista.txt"
  cat > "$SANDBOX/fetch" <<EOF
#!/usr/bin/env bash
echo "\$2" >> "$SANDBOX/fetch.log"
cp "$SANDBOX/files/\$(basename "\$2")" "\$1"
EOF
  chmod +x "$SANDBOX/fetch"
  export FERRAMENTAS_LIST="$SANDBOX/lista.txt" JARVIS_FETCH="$SANDBOX/fetch"
  INST="$REPO_ROOT/ci/instalar-ferramentas.sh"
}

@test "instala, confere o checksum e liga o binário em DIR/bin" {
  run "$INST" "$SANDBOX/dest"
  [ "$status" -eq 0 ]
  [ "$("$SANDBOX/dest/bin/foo")" = foo-ok ]
  [ -f "$SANDBOX/dest/opt/foo-1.0/.ok" ]
}

@test "checksum errado aborta e não deixa binário instalado" {
  sed -i 's/ [0-9a-f]\{64\} / 0000000000000000000000000000000000000000000000000000000000000000 /' "$SANDBOX/lista.txt"
  run "$INST" "$SANDBOX/dest"
  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum"* ]]
  [ ! -e "$SANDBOX/dest/bin/foo" ]
}

@test "segunda execução não baixa de novo" {
  "$INST" "$SANDBOX/dest"
  "$INST" "$SANDBOX/dest"
  [ "$(wc -l < "$SANDBOX/fetch.log")" -eq 1 ]
}

@test "instalação interrompida (sem .ok) é refeita com checksum" {
  "$INST" "$SANDBOX/dest"
  rm "$SANDBOX/dest/opt/foo-1.0/.ok"
  echo lixo > "$SANDBOX/dest/opt/foo-1.0/foo"
  run "$INST" "$SANDBOX/dest"
  [ "$status" -eq 0 ]
  [ "$("$SANDBOX/dest/bin/foo")" = foo-ok ]
  [ "$(wc -l < "$SANDBOX/fetch.log")" -eq 2 ]
}

@test "instala só as ferramentas pedidas" {
  printf 'bar 2.0 https://github.com/x/bar/bar.tar.gz %s bar/bar\n' "$(printf '0%.0s' {1..64})" >> "$SANDBOX/lista.txt"
  run "$INST" "$SANDBOX/dest" foo
  [ "$status" -eq 0 ]
  [ -e "$SANDBOX/dest/bin/foo" ]
  [ ! -e "$SANDBOX/dest/bin/bar" ]
}

@test "ci/ferramentas.txt real: 5 campos, URL do GitHub, sha256 de 64 hex" {
  while read -r nome versao url sha bin; do
    [[ -z $nome || $nome == \#* ]] && continue
    [[ -n $bin ]] || { echo "campos faltando: $nome"; return 1; }
    [[ $url == https://github.com/* ]] || { echo "url: $nome"; return 1; }
    [[ $sha =~ ^[0-9a-f]{64}$ ]] || { echo "sha: $nome"; return 1; }
  done < "$REPO_ROOT/ci/ferramentas.txt"
  for n in shellcheck bats gitleaks actionlint zizmor lynis; do
    grep -q "^$n " "$REPO_ROOT/ci/ferramentas.txt" || { echo "faltando: $n"; return 1; }
  done
}
