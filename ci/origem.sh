#!/usr/bin/env bash
# origem — regra do GitLab flow: o prod só recebe o que já está no main.
#   - PR para o prod precisa vir do branch main;
#   - todo commit (fora os de merge) alcançável a partir do prod precisa existir no main.
# Sem proteção de branch no GitHub gratuito, é este job que denuncia um push direto no prod.
set -euo pipefail

EVENT=${EVENT:-push}
HEAD_REF=${HEAD_REF:-}
MAIN_REF=${MAIN_REF:-origin/main}
TARGET=${TARGET:-HEAD}

falha() { echo "origem: $*" >&2; exit 1; }

if [[ $EVENT == pull_request && $HEAD_REF != main ]]; then
  falha "PR para o prod precisa vir do main (veio de '$HEAD_REF')"
fi

extras=$(git log --no-merges --format='%h %s' "$MAIN_REF..$TARGET")
if [[ -n $extras ]]; then
  falha "commits no prod que não estão no main (siga feat/* → main → prod):
$extras"
fi
# --no-merges acima não enxerga alterações feitas DENTRO de um merge ("merge maligno").
# Num release legítimo (prod ⊆ main), o merge fica idêntico ao lado do main (2º pai).
while read -r m; do
  git diff --quiet "$m^2" "$m" ||
    falha "merge $(git log -1 --format='%h %s' "$m") traz alterações que não estão no main"
done < <(git rev-list --merges "$MAIN_REF..$TARGET")
echo "origem: ok — tudo no prod veio do main"
