# The Bintana release actions

The release workflow every Bintana application shares: one call builds a
**Flatpak bundle** and a **Windows setup**, and a GitHub release in the
application's own repository carries them.

**Nothing here names an application.** The project is the calling
repository's, and the workflow reads its `project.btp`, its metainfo and its
icon -- the same four things `tools/pack.sh` reads. Adding a release to an
application is copying one file and pushing a tag.

## In an application

Copy [`templates/release.yml`](templates/release.yml) to
`.github/workflows/release.yml` -- it is the whole integration -- and then:

```sh
git tag v0.1
git push origin v0.1
```

The tag publishes. *Actions → release → Run workflow*, with the box unticked,
only builds: the two files are left as artifacts of the run, and nothing is
released.

The project must have:

| | |
|---|---|
| `project.btp` | an `id` (reverse-DNS) and a `version`; `name` is checked against the metainfo |
| `<id>.metainfo.xml` | beside it, with the same `<id>` and primary `<name>` |
| `icons/<id>.svg` or `icons/<id>.png` | AppStream will not compose an application without one |

and the calling workflow needs `permissions: contents: write`, which the
template declares.

**A project with only an SVG icon builds**, and the Windows setup wears the
generic icon: NSIS cannot wear an SVG. Add `icons/<id>.png` for the shortcut
and *Installed apps*.

## What it publishes

One release, at the tag (`v0.1`), with:

| file | what |
|---|---|
| `bintana-draw-0.1-linux-x86_64.flatpak` | the application, on the BaseApp |
| `bintana-draw-0.1-windows-x86_64.exe` | the per-user setup, runtime included |
| `*.sha256` | one digest per file |

`<command>` is `bintana-` and the id's last element (`io.github.…Draw` →
`bintana-draw`), the name a menu runs. A version with a letter in it
(`0.2.0rc1`) is a prerelease.

A rebuild under the same tag -- the runtime moved, the application did not --
replaces the assets in place: it is the same release, rebuilt.

The Flatpak bundle carries the application and not the runtime, so installing
it needs the Bintana repository first:

```sh
flatpak remote-add --if-not-exists bintana https://getbintana.github.io/flatpak/
flatpak install ./bintana-draw-0.1-linux-x86_64.flatpak
```

The release notes carry those two lines, and the commit of the application
and of the runtime the files were built from.

## Inputs

| input | default | |
|---|---|---|
| `project` | `.` | the project below the repository root |
| `finish_args` | `""` | Flatpak sandbox permissions, comma separated; **they replace** the default `--share=ipc`, Wayland, fallback X11 and DRI, so an application that opens the user's files names all of them |
| `with_paths` | `""` | runtime-tree paths the Windows setup carries besides the runtime, one per line (`share/bintana/examples`); a path the tree does not have stops the release |
| `bintana_ref` | `""` | the `getbintana/bintana` ref; empty is its **newest tag** |
| `actions_ref` | `""` | this repository's ref to take the scripts from; empty is the ref the workflow was called at |
| `tag` | `""` | the tag to publish under; empty is `v<version>`, and a tag that is not `v` and the version is refused |
| `publish` | `true` | create or refresh the release |
| `flatpak` | `true` | build the bundle |
| `windows` | `true` | build the setup |

## The runtime

Every release compiles the runtime it packages: the Windows setup carries its
own copy of it, and the Flatpak is built on the BaseApp the runtime version
names. Empty `bintana_ref` is the runtime's newest tag -- a tagged runtime is
a known source, and its version is the BaseApp branch the bundle needs; with
no tag, the default branch. Pin `bintana_ref` in the calling workflow when a
release has to be reproducible.

The runtime's commit is resolved and recorded in the notes. A branch is
accepted, and is then whatever that branch was when the job checked it out.

## What runs before publishing

Each product is installed and run, and a failure stops the release:

- **Flatpak**: the deployment has the launcher, the desktop entry and the
  metainfo a desktop looks for; `bintana --version` answers from the package;
  one console project runs out of it.
- **Windows**: the setup is installed silently (`/S`, no elevation) and the
  installed tree answers `--version`, runs one console project, and runs the
  graphical host's probe -- `Video`, `PdfDocument.CanRead` and `Terminal`,
  which a payload loses quietly. The launcher, the icon themes, the licences
  and the redistributed DLLs (`vulkan-1.dll`, `librsvg-2-2.dll`,
  `libvterm-0.dll`) are checked, with only Windows' own directories on the
  PATH.

## Trying it without a tag

```sh
scripts/plan.py path/to/project                 # id, command, version, tag
scripts/flatpak.sh path/to/project /tmp/app.flatpak /path/to/bintana <id>
```

`flatpak.sh` needs the runtime built at `<bintana>/build/bintana` and installs
the BaseApp from the published repository. `tests/plan.sh` runs the planner
over fixtures. The Windows half needs Windows (MSYS2 UCRT64 and `makensis`):
`scripts/nsis.sh` is what the workflow calls.

## What it does not do

- **No signing.** The bundle is unsigned, and the release is the
  application's own rather than the published OSTree repository's.
- **No rebuild planning.** Every run builds both products from scratch; the
  central `getbintana/flatpak` and `getbintana/windows` repositories still
  exist for the shared repository and for rebuilding only what changed.

## Layout

| | |
|---|---|
| `.github/workflows/app-release.yml` | the reusable workflow (`workflow_call`) |
| `templates/release.yml` | the file an application copies |
| `scripts/plan.py` | the identity, version and tag, and the early refusals |
| `scripts/flatpak.sh` | manifest, build, bundle |
| `scripts/nsis.sh` | the setup |
| `scripts/smoke-linux.sh`, `scripts/smoke-windows.sh` | what is run before publishing |
| `scripts/release.py` | the release, idempotently |
| `smoke/` | the console project and the graphical probe |
| `tests/plan.sh` | the planner's tests |
