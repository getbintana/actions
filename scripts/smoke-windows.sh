#!/usr/bin/env bash
#
# What an installed Windows setup must answer before it is published.
#
#   scripts/smoke-windows.sh <setup> <command> <with-file> <console> <probe>
#
# The setup is installed silently (`/S`, the per-user installer, no elevation)
# into a directory of the run's own, and the installed tree is asked the
# questions only it can answer -- the central windows job's smoke, moved
# beside the workflow so every project's release runs the same one:
#
#  - the launcher the shortcut starts and the project it starts are there;
#  - the two hosts and the helper keep their subsystems;
#  - the icon themes, the licences and the DLLs a redistributed GTK needs;
#  - `bintana.exe --version`, which is the DLL closure;
#  - one console project, in the installed tree;
#  - the graphical host's probe: a child with its output piped, and `Video`,
#    `PdfDocument.CanRead` and `Terminal`, which a payload loses quietly.
#
# Both executable runs use only Windows' own directories on the PATH: this
# shell has `/ucrt64/bin`, which holds every DLL the tree should carry, and a
# run here would find a missing one there and pass.
set -euo pipefail

usage="usage: scripts/smoke-windows.sh <setup> <command> <with-file> <console> <probe>"

setup=$(realpath "${1:?$usage}")
command=${2:?$usage}
with_file=${3:?$usage}
console=$(realpath "${4:?$usage}")
probe=$(realpath "${5:?$usage}")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Copies, because the probe writes its answers beside the project and a
# checkout is not a place to write.
cp -r "$console" "$work/console"
cp -r "$probe" "$work/probe"
console="$work/console"
probe="$work/probe"

into=$(cygpath -u "$RUNNER_TEMP")/install
rm -rf "$into"
mkdir -p "$into"

echo "-- $(basename "$setup")"
MSYS2_ARG_CONV_EXCL='*' "$setup" /S "/D=$(cygpath -w "$into")"

test -f "$into/bin/$command.cmd"
test -f "$into/share/bintana/apps/$command/project.btp"
test -f "$into/Uninstall.exe"

# What a shortcut starts is the GUI host; `bintana-exec.exe` is GUI so a
# console tool an application runs has no window of its own; the core is
# console, which `--version` wants.
objdump -p "$into/bin/bintana-gui.exe" | grep -q 'Windows GUI' \
    || { echo "smoke: bintana-gui.exe is not a GUI executable" >&2; exit 1; }
objdump -p "$into/bin/bintana.exe" | grep -q 'Windows CUI' \
    || { echo "smoke: bintana.exe is not a console executable" >&2; exit 1; }
objdump -p "$into/bin/bintana-exec.exe" | grep -q 'Windows GUI' \
    || { echo "smoke: bintana-exec.exe is not a GUI executable" >&2; exit 1; }

# Adwaita inherits AdwaitaLegacy, where its full-colour icons are.
for theme in Adwaita AdwaitaLegacy hicolor; do
    test -f "$into/share/icons/$theme/index.theme" \
        || { echo "smoke: installed without the $theme icon theme" >&2; exit 1; }
done

while IFS= read -r path; do
    [[ -z $path ]] || test -e "$into/$path" \
        || { echo "smoke: installed without $path" >&2; exit 1; }
done < "$with_file"

# `share/doc/bintana` is README, CHANGELOG and the notices, never the
# contributors' `docs/` (the notes, the plans, the audit).
if grep -qx 'share/doc/bintana' "$with_file" 2>/dev/null; then
    for doc in README.md CHANGELOG.md; do
        test -f "$into/share/doc/bintana/$doc" \
            || { echo "smoke: installed without share/doc/bintana/$doc" >&2; exit 1; }
    done
    [ ! -d "$into/share/doc/bintana/docs" ] \
        || { echo "smoke: installed the contributors' docs/ beside the release" >&2; exit 1; }
fi

# The DLLs a setup redistributes carry their notices: Bintana's, QuickJS's
# (the engine is embedded) and the MSYS2 packages' texts.
for file in LICENSE-Bintana LICENSE-QuickJS THIRD-PARTY-NOTICES.md \
            MSYS2-PACKAGES.md; do
    test -f "$into/share/licenses/bintana/$file" \
        || { echo "smoke: installed without share/licenses/bintana/$file" >&2; exit 1; }
done

# GTK imports vulkan-1.dll at load time, the SVG loader imports
# librsvg-2-2.dll and the graphical host imports libvterm-0.dll: none is
# Windows' own, and a runner's System32 has a Vulkan loader, so a setup
# missing one still runs here and fails on a machine whose driver ships none.
for dll in vulkan-1.dll librsvg-2-2.dll libvterm-0.dll; do
    test -f "$into/bin/$dll" \
        || { echo "smoke: installed without $dll" >&2; exit 1; }
done

clean="/c/Windows/System32:/c/Windows"

PATH="$clean" "$into/bin/bintana.exe" --version
PATH="$clean" "$into/bin/bintana.exe" "$console"

# No console, so nothing the graphical host prints is seen: its answers go to
# a file, and the exit code says whether it ran.
rm -f "$probe/answer.txt"
PATH="$clean" "$into/bin/bintana-gui.exe" "$probe" \
    || { cat "$probe/answer.txt" 2>/dev/null || true
         echo "smoke: bintana-gui.exe could not run the probe" >&2; exit 1; }

answers=$(cat "$probe/answer.txt")
echo "$answers"
for want in 'exec=0' 'video=true' 'pdf=true' 'terminal=true'; do
    grep -qx "$want" <<<"$answers" \
        || { echo "smoke: the installed tree did not answer $want" >&2; exit 1; }
done
