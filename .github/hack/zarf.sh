#!/usr/bin/env bash

set -e
set -u
set -o pipefail

declare -a FLAVOR=("upstream")

export pkg="local-path"

for flavor in "${FLAVOR[@]}"; do
  echo "::debug::flavor='${flavor}'"
  rm -rf .direnv/$flavor
  mkdir -p .direnv/$flavor
  zarf dev find-images --flavor $flavor --skip-cosign . 2>/dev/null > .direnv/$flavor/out.yml
  yq -i '... comments=""' .direnv/$flavor/out.yml
  export yq_search=$(printf '.components[] | select(.name == "%s-images" and .selector.flavor == "%s") | path | .[1]' "$pkg" "$flavor")
  echo "::debug::yq_search='${yq_search}'"
  export yq_index=$(yq "$yq_search" zarf.yaml)
  echo "::debug::yq_index='${yq_index}'"
  export yq_images=$(printf '(select(fi == 1) | .components[] | select(.name == "%s-chart") | .images | ... head_comment="") as $img' "$pkg")
  echo "::debug::yq_images='${yq_images}'"
  export yq_charts=$(printf '(select(fi == 0) | [.x-artifacts.chart[] | {"name": .}]) as $art')
  echo "::debug::yq_charts='${yq_charts}'"
  export yq_old=$(printf '(select(fi == 0) | .components[%s].images // []) as $old' "$yq_index")
  echo "::debug::yq_old='${yq_old}'"
  # carry hand-written per-image fields (id, source) over to the regenerated list; matched on the
  # repository alone so the fields survive a tag or digest bump
  export yq_repo='(sub("@.*"; "") | sub(":[^:/]*$"; ""))'
  export yq_update=$(printf '(select(fi == 0) | .components[%s].images = ($img + $art | sort_by(.name) | map(. as $cur | ($old | map(select((.name | %s) == ($cur.name | %s))) | .[0] // {}) * $cur)))' "$yq_index" "$yq_repo" "$yq_repo")
  echo "::debug::yq_update='${yq_update}'"
  export yq_comments=$(printf '(select(fi == 0) | .components[%s].images[] head_comment="" | .components[%s].images[].name head_comment="")' "$yq_index" "$yq_index")
  echo "::debug::yq_comments='${yq_comments}'"
  yq ea -i "$yq_images | $yq_charts | $yq_old | $yq_update | $yq_comments" zarf.yaml .direnv/$flavor/out.yml
done
