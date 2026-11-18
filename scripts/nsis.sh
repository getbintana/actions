#!/usr/bin/env bash
#
# Compile one Bintana application into a Windows setup.
#
#   scripts/nsis.sh <project> <out> <runtime> <bintana> <command> <version> [<with-file>]
#
# `<runtime>` is the portable tree `tools/windows-portable.sh` laid out (bin/,
# share/, lib/); `<bintana>` is the checkout it was laid out from. `<with-file>`
# is a file of paths inside the runtime tree the installer carries besides the
# runtime, one per line -- the workflow writes it from the `with-paths` input.
# A path the tree does not have stops the run inside `tools/pack.sh`: an
# installer asked to be complete is never quietly not.
#
# What it leaves is the setup `tools/pack.sh` names itself
# (`<command>-<version>-windows-x86_64.exe`) and its `.sha256`. Run it on
# Windows, from Git Bash or MSYS2, with `makensis` on the PATH (or in the
# runtime's `share/bintana/tools/nsis`, where `Nsis.makensis` looks first).
set -euo pipefail

usage="usage: scripts/nsis.sh <project> <out> <runtime> <bintana> <command> <version> [<with-file>]"

project=$(realpath "${1:?$usage}")
out=$(realpath -m "${2:?$usage}")
runtime=$(realpath "${3:?$usage}")
bintana=$(realpath "${4:?$usage}")
command=${5:?$usage}
version=${6:?$usage}
with_file=${7:-}

[[ -x $runtime/bin/bintana.exe ]] || {
    echo "nsis: no runtime at $runtime/bin/bintana.exe" >&2
    exit 2
}
[[ -f $bintana/tools/pack.sh ]] || {
    echo "nsis: no bintana checkout at $bintana" >&2
    exit 2
}

extra=()
if [[ -n $with_file && -s $with_file ]]; then
    while IFS= read -r path; do
        [[ -z $path ]] || extra+=(--with "$path")
    done < "$with_file"
fi

mkdir -p "$out"
rm -f "$out"/*-windows-x86_64.exe "$out"/*-windows-x86_64.exe.sha256 2>/dev/null || true

BINTANA="$runtime/bin/bintana.exe" \
    "$bintana/tools/pack.sh" --nsis "$project" "$out" \
    --prefix "$runtime" "${extra[@]}"

setup="$out/$command-$version-windows-x86_64.exe"
[[ -f $setup ]] || {
    echo "nsis: pack wrote no $(basename "$setup")" >&2
    ls -l "$out" >&2
    exit 2
}

( cd "$(dirname "$setup")" && sha256sum "$(basename "$setup")" \
      > "$(basename "$setup").sha256" )

echo "$setup"
