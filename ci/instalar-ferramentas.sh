#!/usr/bin/env bash
# instalar-ferramentas — instala as ferramentas de ci/ferramentas.txt em DIR, conferindo o SHA-256.
#   ci/instalar-ferramentas.sh DIR [NOME...]     (sem NOME: todas)
# Cada ferramenta vai para DIR/opt/<nome>-<versão>/ e o binário é ligado em DIR/bin/<nome>.
# Checksum diferente do registrado = aborta. Mesmo script no CI e no seu computador.
set -euo pipefail

dest=${1:?uso: ci/instalar-ferramentas.sh DIR [NOME...]}
shift
list=${FERRAMENTAS_LIST:-$(dirname "$(readlink -f "$0")")/ferramentas.txt}
read -r -a fetch <<<"${JARVIS_FETCH:-curl -fsSL -o}"

die() { echo "instalar-ferramentas: $*" >&2; exit 1; }

wanted() {
  (($# == 0)) && return 0
  local n=$1
  shift
  local w
  for w in "${WANTED[@]}"; do [[ $w == "$n" ]] && return 0; done
  return 1
}

WANTED=("$@")
mkdir -p "$dest/bin" "$dest/opt" "$dest/cache"

while read -r name version url sha bin; do
  [[ -z ${name:-} || $name == \#* ]] && continue
  if ((${#WANTED[@]})) && ! wanted "$name" x; then continue; fi
  target="$dest/opt/$name-$version"
  if [[ ! -f $target/.ok ]]; then
    file="$dest/cache/$name-$version-$(basename "$url")"
    rm -f "$file"
    "${fetch[@]}" "$file" "$url" || die "download falhou: $url"
    if ! echo "$sha  $file" | sha256sum -c --quiet - >/dev/null 2>&1; then
      rm -f "$file"
      die "checksum NÃO confere para $name $version — nada foi instalado"
    fi
    rm -rf "$target"
    mkdir -p "$target"
    tar -xf "$file" -C "$target"
    [[ -x $target/$bin ]] || die "binário não encontrado no pacote: $bin"
    touch "$target/.ok"
  fi
  ln -sfn "../opt/$name-$version/$bin" "$dest/bin/$name"
  echo "ok $name $version"
done <"$list"
