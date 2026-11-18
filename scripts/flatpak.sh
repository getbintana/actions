#!/usr/bin/env bash
#
# Build one Bintana application as a Flatpak bundle.
#
#   scripts/flatpak.sh <project> <bundle> <bintana> <id> [--finish-args a,b]
#
# `<bintana>` is a checkout of `getbintana/bintana` whose `build/bintana` is
# built; the manifest is the one `tools/pack.sh` writes from the project, so
# the project, its metainfo, its entry and its icon are the ones a package
# installs. The bundle carries the application and not the runtime, so
# installing it needs the BaseApp the manifest names -- this installs it from
# the published Bintana repository first, and the release notes tell the
# reader the same two commands.
#
# What it leaves is `<bundle>`, a file `flatpak install ./<bundle>` takes, and
# `<bundle>.sha256` beside it. The build (and the application) is installed in
# the user's own installation because `flatpak-builder --install` is what makes
# the smoke step in the workflow run the package it just built.
set -euo pipefail

usage="usage: scripts/flatpak.sh <project> <bundle> <bintana> <id> [--finish-args a,b]"

project=$(realpath "${1:?$usage}")
bundle=$(realpath -m "${2:?$usage}")
bintana=$(realpath "${3:?$usage}")
id=${4:?$usage}
shift 4

finish=""
if [[ ${1:-} == --finish-args ]]; then
    finish=${2:?--finish-args needs a comma-separated list}
    shift 2
fi
[[ $# -eq 0 ]] || { echo "flatpak: unexpected arguments: $*" >&2; exit 2; }

[[ -x $bintana/build/bintana ]] || {
    echo "flatpak: no runtime at $bintana/build/bintana -- build it first" >&2
    exit 2
}

remote=${BINTANA_FLATPAK_REMOTE:-https://getbintana.github.io/flatpak/}
flatpak remote-add --user --if-not-exists --no-gpg-verify bintana "$remote"
flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

BINTANA=$bintana/build/bintana "$bintana/tools/pack.sh" "$project" "$work/context" \
    ${finish:+--finish-args "$finish"}

manifest="$work/context/$id.json"
[[ -f $manifest ]] || { echo "flatpak: no $manifest after pack" >&2; exit 2; }

read_base() {
    python3 -c '
import json, sys
manifest = json.load(open(sys.argv[1]))
print(manifest.get(sys.argv[2], ""))
' "$manifest" "$1"
}

base=$(read_base base-version)
branch=$(read_base branch)
base=${base:-0.4}
branch=${branch:-stable}
base_ref="io.github.getbintana.BaseApp//$base"

# The base is baked into the package at build time, and the published
# repository is where it is. `--or-update` is what makes "already installed" a
# success instead of a failure to swallow.
flatpak install --user -y --noninteractive --or-update bintana "$base_ref" || {
    echo "flatpak: cannot install $base_ref from $remote" >&2
    echo "flatpak: is BaseApp $base published there? see getbintana/flatpak" >&2
    exit 2
}

# The state directory stays under the same temp tree as the build directory:
# flatpak-builder refuses two filesystems, and its default state dir is
# `./.flatpak-builder` -- the checkout -- while the build dir is under `/tmp`.
flatpak-builder --user --install --force-clean --install-deps-from=flathub \
    --state-dir="$work/state" \
    --repo="$work/repo" "$work/build" "$manifest"

mkdir -p "$(dirname "$bundle")"
rm -f "$bundle" "$bundle.sha256"
flatpak build-bundle "$work/repo" "$bundle" "$id" "$branch"
( cd "$(dirname "$bundle")" && sha256sum "$(basename "$bundle")" \
      > "$(basename "$bundle").sha256" )

echo "$bundle"
