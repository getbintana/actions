#!/usr/bin/env python3
"""Publish the assets of one run as a GitHub release, idempotently.

    scripts/release.py <tag> [--title T] [--notes-file F] [--target SHA]
                        [--prerelease] FILE...

A release that already exists is kept and its assets are replaced in place
(`--clobber`), because a rebuild under the same version -- the runtime moved,
the application did not -- is the same release, rebuilt. Its body is rewritten
with the notes of this run, since the asset under the tag is now a different
build.

`GH_REPO` names the repository when the script does not run in its checkout
(the workflow's `ci` checkout is getbintana/actions, not the application's).
"""
import argparse
import os
import subprocess
import sys


def run(args, **kwargs):
    return subprocess.run(["gh", *args], text=True, **kwargs)


def main():
    ap = argparse.ArgumentParser(description="publish one Bintana release")
    ap.add_argument("tag")
    ap.add_argument("--title", default="")
    ap.add_argument("--notes-file", default="")
    ap.add_argument("--target", default="")
    ap.add_argument("--prerelease", action="store_true")
    ap.add_argument("files", nargs="+")
    args = ap.parse_args()

    if not os.environ.get("GH_REPO"):
        print("release: GH_REPO is not set", file=sys.stderr)
        return 2

    for path in args.files:
        if not os.path.isfile(path):
            print(f"release: no {path}", file=sys.stderr)
            return 2

    title = args.title or args.tag
    notes = ["--notes-file", args.notes_file] if args.notes_file else []

    seen = run(["release", "view", args.tag], capture_output=True)
    if seen.returncode != 0:
        create = ["release", "create", args.tag, "--title", title, *notes]
        if args.target:
            create += ["--target", args.target]
        if args.prerelease:
            create += ["--prerelease"]
        subprocess.run(["gh", *create], check=True)
    else:
        print(f"release: {args.tag} exists -- replacing its assets")

    subprocess.run(["gh", "release", "upload", args.tag, *args.files,
                    "--clobber"], check=True)

    if args.notes_file:
        subprocess.run(["gh", "release", "edit", args.tag, *notes], check=True)

    for path in args.files:
        print(f"release: {os.path.basename(path)} in {args.tag}")


if __name__ == "__main__":
    sys.exit(main())
