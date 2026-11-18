#!/usr/bin/env python3
"""What a release of a Bintana project is: its identity, version and tag.

    scripts/plan.py <project-dir> [--ref REF] [--tag TAG]

Prints one JSON object:

    {"id": "io.github.getbintana.Draw", "name": "Bintana Draw",
     "command": "bintana-draw", "version": "0.1", "tag": "v0.1",
     "prerelease": false, "project": "/path/to/the/project"}

`--ref` is the full ref that started the run (`refs/tags/v0.1`,
`refs/heads/main`). A tag must be `v` and the version, and the version must
not carry the `v` -- the rule `tools/release-tag.sh` applies to the runtime,
applied to an application. `--tag` names the release explicitly and is
checked by the same rule.

**The checks that need no build happen here**, so a project that cannot be
packaged fails in seconds instead of after a runtime has been compiled on two
runners: the id, the metainfo that has to agree with it, and the icon.
`tools/pack.sh` is still the authority and repeats them; this is the early
copy, and it is deliberately only the cheap half.
"""
import argparse
import glob
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"

# `Package.configOf`'s rule: reverse-DNS, one or more dots, no character that
# would land in a file name or a shell command.
ID = re.compile(r"^[A-Za-z_-][A-Za-z0-9_-]*(\.[A-Za-z_-][A-Za-z0-9_-]*)+$")


def die(message):
    print(f"plan: {message}", file=sys.stderr)
    sys.exit(1)


def config(project):
    path = os.path.join(project, "project.btp")
    if not os.path.isfile(path):
        path = os.path.join(project, "project.json")
    if not os.path.isfile(path):
        die(f"{project} has no project.btp -- not a Bintana project?")
    with open(path, encoding="utf-8") as f:
        try:
            return json.load(f)
        except ValueError as e:
            die(f"{path} is not JSON: {e}")


def metainfo(project, id, name):
    """The metainfo's `<id>` and primary `<name>`, checked against project.btp.

    The file is found by suffix, as `lib/package/Metainfo.find` does: the id
    may have moved since the file was written, and that is exactly the state
    the check reports.
    """
    found = sorted(glob.glob(os.path.join(project, "*.metainfo.xml")))
    if not found:
        die(f"the project ships no {id}.metainfo.xml -- a package needs one, "
            f"and the IDE's Application info writes it")
    path = found[0]

    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        die(f"{path} is not XML: {e}")

    def children(name):
        for element in root:
            if element.tag.rsplit("}", 1)[-1] == name:
                yield element

    seen_id = next((e.text or "" for e in children("id")), "").strip()
    name_element = next(
        (e for e in children("name") if e.get(XML_LANG) is None), None)
    seen_name = (name_element.text or "").strip() if name_element is not None else ""

    if seen_id != id:
        die(f"{os.path.basename(path)} declares <id>{seen_id}</id> and "
            f"project.btp says {id}")
    if seen_name != name:
        die(f"{os.path.basename(path)} declares <name>{seen_name}</name> and "
            f"project.btp says {name}")
    return seen_name


def icon(project, id):
    directory = os.path.join(project, "icons")
    wanted = f"icons/{id}.svg or icons/{id}.png"
    if os.path.isdir(directory):
        for ext in ("svg", "png"):
            if os.path.isfile(os.path.join(directory, f"{id}.{ext}")):
                return
        drawn = [
            f for f in os.listdir(directory)
            if f.lower().endswith((".svg", ".png"))
            and not re.search(r"-symbolic$", os.path.splitext(f)[0], re.I)
        ]
        if len(drawn) == 1:
            return
        if len(drawn) > 1:
            die(f"icons/ holds {len(drawn)} drawings ({', '.join(sorted(drawn))}) "
                f"and none is named after the id -- name the application's own "
                f"{wanted}")
    die(f"the project ships no icon -- put {wanted} in the project, because "
        f"AppStream will not compose an application without one")


def main():
    ap = argparse.ArgumentParser(
        description="the identity, version and tag of one Bintana release")
    ap.add_argument("project", help="the project directory (project.btp)")
    ap.add_argument("--ref", default="",
                    help="the ref that started the run, e.g. refs/tags/v0.1")
    ap.add_argument("--tag", default="", help="the tag to publish under")
    args = ap.parse_args()

    project = os.path.abspath(args.project)
    if not os.path.isdir(project):
        die(f"{args.project} is not a directory")

    config_ = config(project)

    id = config_.get("id")
    if not isinstance(id, str) or not ID.match(id):
        die(f'"{id}" is not an application id -- a reverse-DNS name like '
            f"io.github.you.App, which is what a package installs under")
    name = config_.get("name")
    if not isinstance(name, str) or not name.strip():
        die("the project declares no name -- the metainfo's <name> is checked "
            "against it")

    version = str(config_.get("version") or "").strip()
    if not version:
        die("the project declares no version -- a release is named after it")
    if version.startswith("v"):
        die(f'the version carries the "v" ({version}); only a tag is v and the '
            f"version, and this would publish v{version}")

    if args.tag:
        tag = args.tag
    elif args.ref.startswith("refs/tags/"):
        tag = args.ref[len("refs/tags/"):]
    else:
        tag = f"v{version}"

    if tag != f"v{version}":
        die(f"the tag is {tag} and the project's version is {version} -- a "
            f"release of {version} is v{version}")

    metainfo(project, id, name)
    icon(project, id)

    # The command a menu runs, `Package.commandName`: a package and a setup
    # both name themselves from it, so the workflow doesn't spell it twice.
    last = id.split(".")[-1].lower()
    last = re.sub(r"[^a-z0-9]+", "-", last).strip("-")
    command = f"bintana-{last or 'app'}"

    # What the setup's file name carries: `Nsis.setupVersion` replaces a run of
    # characters outside [A-Za-z0-9.] with one `-`, and the Flatpak bundle is
    # named the same way so the two assets read alike.
    file_version = re.sub(r"[^A-Za-z0-9.]+", "-", version) or "0.0"

    plan = {
        "id": id,
        "name": name,
        "command": command,
        "version": version,
        "file_version": file_version,
        "tag": tag,
        # A version with a letter in it is a prerelease, so the repository's
        # "latest" stays on the last final one -- the runtime's own rule.
        "prerelease": bool(re.search(r"[A-Za-z]", version)),
        "project": project,
    }
    print(json.dumps(plan, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
