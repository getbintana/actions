#!/usr/bin/env bash
# The planner against fixtures: what a release is, and the refusals.
#
#   tests/plan.sh
#
# It needs nothing but python3: the checks the planner makes are the ones that
# need no build (the id, the metainfo, the icon, the version and the tag), and
# they are the ones a project tends to get wrong once.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

project() {  # <dir> <name> <id> <version>
    mkdir -p "$1/icons"
    cat > "$1/project.btp" <<EOF
{
    "name": "$2",
    "id": "$3",
    "version": "$4"
}
EOF
    cat > "$1/$3.metainfo.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>$3</id>
  <name>$2</name>
  <name xml:lang="es">$2</name>
</component>
EOF
    printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' > "$1/icons/$3.svg"
}

expect() {  # <what> <json key> <value> <args...>
    local what=$1 key=$2 want=$3
    shift 3
    local out got
    out=$(python3 "$here/scripts/plan.py" "$@")
    got=$(python3 -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' \
              "$key" <<<"$out")
    if [ "$got" != "$want" ]; then
        echo "plan: $what: $key is '$got', wanted '$want'" >&2
        exit 1
    fi
}

refuses() {  # <what> <args...>
    local what=$1
    shift
    if python3 "$here/scripts/plan.py" "$@" >/dev/null 2>&1; then
        echo "plan: $what was accepted" >&2
        exit 1
    fi
}

project "$tmp/draw" "Bintana Draw" io.github.getbintana.Draw 0.1
expect "id" id io.github.getbintana.Draw "$tmp/draw"
expect "command" command bintana-draw "$tmp/draw"
expect "tag" tag v0.1 "$tmp/draw"
expect "prerelease" prerelease False "$tmp/draw"
expect "from a tag" tag v0.1 "$tmp/draw" --ref refs/tags/v0.1
expect "from a branch" tag v0.1 "$tmp/draw" --ref refs/heads/main
expect "an explicit tag" tag v0.1 "$tmp/draw" --tag v0.1

# The translations of `<name>` are not the primary name, and are not compared.
project "$tmp/rc" "Bintana Test" io.github.getbintana.Test 0.2.0rc1
expect "prerelease" prerelease True "$tmp/rc"
expect "rc tag" tag v0.2.0rc1 "$tmp/rc"
expect "rc file version" file_version 0.2.0rc1 "$tmp/rc"

refuses "a tag of another version" "$tmp/draw" --ref refs/tags/v9.9
refuses "a tag without the v" "$tmp/draw" --tag 0.1

project "$tmp/bad-id" "Bintana Test" Bad 1.0
refuses "an id that is not reverse-DNS" "$tmp/bad-id"

project "$tmp/no-version" "Bintana Test" io.github.getbintana.Test ""
refuses "a project with no version" "$tmp/no-version"

project "$tmp/no-icon" "Bintana Test" io.github.getbintana.Test 1.0
rm "$tmp/no-icon/icons/io.github.getbintana.Test.svg"
refuses "a project with no icon" "$tmp/no-icon"

project "$tmp/no-metainfo" "Bintana Test" io.github.getbintana.Test 1.0
rm "$tmp/no-metainfo/io.github.getbintana.Test.metainfo.xml"
refuses "a project with no metainfo" "$tmp/no-metainfo"

project "$tmp/wrong-name" "Bintana Draw" io.github.getbintana.Draw 1.0
sed -i 's/Bintana Draw/Bintana Other/' \
    "$tmp/wrong-name/io.github.getbintana.Draw.metainfo.xml"
refuses "a metainfo whose name disagrees" "$tmp/wrong-name"

project "$tmp/wrong-id" "Bintana Draw" io.github.getbintana.Draw 1.0
sed -i 's/io.github.getbintana.Draw/io.github.getbintana.Other/' \
    "$tmp/wrong-id/io.github.getbintana.Draw.metainfo.xml"
refuses "a metainfo whose id disagrees" "$tmp/wrong-id"

echo "plan: ok"
