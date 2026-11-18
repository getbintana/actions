#!/usr/bin/env bash
#
# What an installed Flatpak must answer before it is published.
#
#   scripts/smoke-linux.sh <id> <command> <console-project>
#
# The same smoke the central flatpak repository runs, for one application:
# the files a desktop looks for are in the deployment, the runtime in the
# package answers `--version`, and one console project runs out of it -- a
# `main` project never initialises GTK, so it needs no display.
set -euo pipefail

usage="usage: scripts/smoke-linux.sh <id> <command> <console-project>"

id=${1:?$usage}
command=${2:?$usage}
console=$(realpath "${3:?$usage}")

location=$(flatpak info --user --show-location "$id") || {
    echo "smoke: $id is not installed" >&2
    exit 2
}

for file in \
    "bin/$command" \
    "share/applications/$id.desktop" \
    "share/metainfo/$id.metainfo.xml"
do
    test -f "$location/files/$file" \
        || { echo "smoke: $id has no $file" >&2; exit 1; }
done

echo "-- $id: $(flatpak info --user --show-ref "$id")"
flatpak run --command=bintana "$id" --version

# `--filesystem` is the run-time sandbox override, and the console project is
# a directory of the runner's: without it the sandbox cannot read it.
flatpak run --command=bintana --filesystem="$console" "$id" "$console"
