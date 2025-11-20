# git-pkgs — the git-native package manager

`git-pkgs` lets any git repository double as a fully self-hosted package registry. Every release, dependency edge, and provenance record is stored under `refs/pkgs/` using stock git data structures—no daemons, lockfiles, or central services required. The latest refactor moves all package metadata into JSON (`pkgs.json`) files that travel with each package, making dependency graphs explicit, reviewable, and easy to automate.

<p align="center">
  <img src="docs/img/git-pkgs.svg" />
</p>

## Why people reach for git-pkgs
- **Registry-free, serverless distribution** – Mirroring the repo copies every dependency because the registry _is_ the repo.
- **Deterministic releases** – `git pkgs release` snapshots the full dependency tree (direct + transitive) into refs you can audit forever.
- **JSON-first configuration** – `pkgs.json` replaces scattered git config keys with a single document per package. It records metadata, dependency revisions, path mappings, and conflict strategy.
- **Safe vendoring via worktrees** – Dependencies live under a configurable prefix (default `pkgs/`) and are checked out as worktrees, so the main branch stays clean.
- **Language agnostic + MCP ready** – Any git content can become a package, and `git pkgs mcp` exposes the same operations over stdio for tool automation.

## How git-pkgs models a package

| Concept | Description |
| --- | --- |
| **Release refs** | Every package `name` and `revision` pair gets a namespace `refs/pkgs/<name>/<revision>/`. `refs/pkgs/<name>/HEAD/` keeps track of the active graph. |
| **`pkgs.json`** | Lives next to your sources. It captures author metadata, default prefix, conflict strategy, and a sorted map of dependencies. `git pkgs add` and `git pkgs release` update it for you. |
| **Worktrees** | Dependencies are checked out into `<prefix>/<package>` (or a custom location from `.paths`). Removing a package just deletes the worktree and ref. |
| **Conflict strategies** | When multiple parents request different revisions of the same package you can pick `max`, `min`, `keep`, `update`, or `interactive`. Defaults can be set per package via `pkgs.json`. |

### `pkgs.json` at a glance

```json
{
  "name": "demo-app",
  "description": "Example service packaged with git-pkgs",
  "version": "1.0.0",
  "prefix": "pkgs",
  "strategy": "max",
  "url": "git@github.com:acme/demo-app.git",
  "dependencies": {
    "core-lib": "v2.1.4",
    "dev:internal-tooling": "HEAD"
  },
  "paths": {
    "core-lib:*": "pkgs",
    "dev:internal-tooling": "tools"
  },
  "scripts": {
    "postcheckout": "./scripts/sync-generated.sh"
  }
}
```

- **Top-level metadata** (`name`, `version`, `description`, `url`, `type`, etc.) describes the package and is stored as git trailers when you cut releases.
- **`dependencies`** is a map from `<namespace>:<package>` (namespace optional) to a revision/tag. Entries are added automatically when you run `git pkgs add`.
- **`paths`** maps namespace patterns to filesystem prefixes. When a package ref matches `<namespace>/<pattern>`, it is checked out into `prefix/<stripped-package-name>`. If omitted, everything lands in `<prefix>/<name>`.
- **`strategy`, `prefix`, `author(s)`, `files`, `config`, `extra`, `scripts`** are optional fields recognised by `PKGS_KEYS` inside `git-pkgs.sh`. Unknown keys are ignored.

Use the built-in config helpers to edit the file without wrangling JSON by hand:

```bash
git pkgs config add name demo-app
git pkgs config add prefix pkgs
git pkgs config add strategy max
git pkgs config list        # prints the normalized JSON
git pkgs config get name    # echoes "demo-app"
```

Pass `--config <path>` to target a different `pkgs.json` and `--pkg-name/--pkg-revision/--pkg-type/--pkg-url` to override metadata while operating on another package (handy when acting as a registry or doing migrations).

## Quick start with the JSON workflow

```bash
# Install once per workstation
sudo ./install.sh

# Create a new repository and describe it via pkgs.json
mkdir demo && cd demo && git init
git pkgs config add name demo-app
git pkgs config add prefix pkgs
git pkgs config add strategy max
echo "pkgs" >> .gitignore            # keep worktrees out of commits

# Add your code, commit it, then bring in a dependency
git pkgs add libfoo v1.2.3 https://github.com/example/libfoo
# pkgs.json is updated; the dependency is checked out under pkgs/libfoo

# Cut a release that freezes the full graph
git commit -am "Initial code"
git tag v1.0.0
git pkgs release -m "demo-app v1.0.0" v1.0.0

# Rehydrate later (locally or on another machine)
git pkgs checkout v1.0.0
git pkgs tree
```

`pkgs.json` is versioned like any other file. Reviewers can diff dependency changes, and automation can parse the JSON directly.

## Command reference

- `git pkgs add [-s <strategy>] [-P <prefix>] [-n <namespace>] <pkg> <revision> [<remote>]`
  Fetches `<pkg>` from `<remote>` (or the stored URL), orphans the requested revision, records it inside `pkgs.json`, then resolves transitive dependencies into `refs/pkgs/<pkg_name>/HEAD/…`. Namespaced adds (e.g. `-n dev`) store dependencies as `dev:<pkg>`.
- `git pkgs add-dir [-n <namespace>] <pkg> <revision> <path>`
  Imports a local directory as a package without running `git init` inside it. Uses a throwaway index, writes trailers, records the dependency in `pkgs.json`, and attaches it to the current graph (useful for Go module cache or npm installs you don't want to mutate).
- `git pkgs remove <pkg>`
  Removes a direct dependency from `HEAD`, deletes the worktree, and reconciles any transitive packages that are no longer needed.
- `git pkgs release [-m <message>] <revision>`
  Writes the current dependency graph into `refs/pkgs/<name>/<revision>/`, updates `pkgs.json.version`, and tags/commits the release.
- `git pkgs checkout <revision>`
  Swaps every dependency worktree to the version recorded in `refs/pkgs/<name>/<revision>/`. Passing `HEAD` restores the working release.
- `git pkgs fetch|pull|push|clone`
  Interact with remotes while keeping `refs/pkgs/` synchronized. `pull` = fetch + checkout; `clone <remote> <dir> [<revision>]` bootstraps a repo plus dependencies in one go.
- `git pkgs ls-releases <pkg>`  
  Lists the remote tags that package has published.
- `git pkgs status`  
  Dumps `<commit>    <name>@<revision>` for every ref currently in the graph.
- `git pkgs tree [<revision>]`  
  Pretty-prints the dependency DAG. Colors highlight whether a package is reused verbatim or deduped.
- `git pkgs show <pkg>`  
  Shows metadata, authorship, refs, and the transitive dependency list for a single package.
- `git pkgs json-export [--all] [<revision>]` / `git pkgs json-import [<file>]`  
  Share dependency manifests across repos or automation. `--all` exports transitive deps, not just the roots.
- `git pkgs config <list|get|add> …`  
  Scriptable interface for editing `pkgs.json`.
- `git pkgs prune`  
  (Advanced) Garbage-collect grafted commits that are no longer reachable.
- `git pkgs mcp`  
  Starts the stdio MCP server so bots or IDEs can drive the same commands programmatically.

Environment variables such as `PKGS_DEFAULT_PREFIX`, `PKGS_DEFAULT_TYPE`, and `PKGS_DEFAULT_STRATEGY` let you seed defaults before invoking commands. The minimum supported git version is 2.41 because git worktree + trailer behaviors rely on it.

## Custom layouts, namespaces, and overrides

- **Paths & prefixes** – Keep multiple dependency groups separated by adding entries under `paths`. A key is either `<namespace>:<pattern>` or `<pattern>`; the value is the filesystem prefix. When a ref under `refs/pkgs/<pkg_name>/HEAD/<namespace>/<pkg>` matches the pattern, the package is checked out under `<prefix>/<trimmed-name>`. Set `"prefix": "false"` when you only need refs and do not want worktrees.
- **Namespace field** – `git pkgs add -n dev foo HEAD` records the dependency as `dev:foo` and expects a matching path pattern when checking out. Namespaces help separate dev/test graphs from production releases without duplicating packages.
- **Overriding metadata** – `--pkg-name`, `--pkg-revision`, `--pkg-type`, and `--pkg-url` allow acting on another package’s refs without switching branches. `npm2pkgs.sh` (below) uses these flags to inject dependencies while building up historical releases.

## Modeling dev-only dependencies

Use namespaces to keep development or test tooling out of production layouts while still recording their provenance inside `pkgs.json`.

1. **Record the dependency under a namespace**
   ```bash
   git pkgs add -n dev tooling-kit HEAD https://github.com/acme/tooling-kit
   ```
   This writes `"dev:tooling-kit": "HEAD"` to `pkgs.json.dependencies`. Release refs still carry the full graph, so you can reproduce local dev environments later.

2. **Map the namespace to a dedicated path**
   ```json
   {
     "paths": {
       "dev:*": "dev_pkgs",
       "*": "pkgs"
     }
   }
   ```
   The first rule sends every `dev:*` package to `dev_pkgs/<name>`, while other dependencies continue to land in `pkgs/<name>`. Patterns can be as specific as needed (`"dev:lint-*": "tools/lint"`).

3. **Gate keep dev packages in releases if desired**
   - For production builds, leave the `dev_pkgs/` directory untracked or ignored (e.g. separate `.gitignore` entry).
   - When cutting a release that should exclude dev tooling entirely, remove the namespace entries from `pkgs.json` before `git pkgs release`—they will no longer be materialized in the target refs.

Because namespaces are first-class in refs (`refs/pkgs/<pkg_name>/HEAD/dev/tooling-kit`), you can always re-checkout or vendor dev dependencies later, yet your runtime workspace stays clean thanks to the `paths` routing.

## Migration helpers (npm, Go, Python, Rust)

Scripts under `migrate/` help import existing projects into git-pkgs:

- Node.js (npm): `migrate/nodejs/npm2pkgs.sh` (+ demo `migrate/nodejs/demo.sh`) reads `npm ls --json` and populates `pkgs.json`.
- Go (modules): `migrate/golang/go2pkgs.sh` (+ demo) parses `go list -m -json all` and can filter to the vendor graph via `--vendor-only`. The script uses the `add-dir` command so transitive refs are resolved into the root graph.
- Python: `migrate/python/pip2pkgs.sh` (requirements.txt) and `migrate/python/poetry2pkgs.sh` (poetry.lock) with demos (`pipdemo.sh`, `poetrydemo.sh`). They create a venv, install deps, synthesize per-package `pkgs.json`, and attach the full tree under the root.
- Rust: `migrate/rust/cargo2pkgs.sh` (+ demo) uses `cargo metadata` to mirror the Cargo dependency graph.

After running the demo scripts you can inspect `DEST/pkgs.json`, run `git pkgs tree`, and start publishing the imported packages just like any native git-pkgs project.

## Further resources

- `docs/mcp.md` – How to speak to the MCP server.
- `migrate/registry.md` – Notes on treating git-pkgs as a general-purpose registry and examples of `--pkg-name` overrides.
- `test/` – Contains end-to-end exercises that showcase nested dependency graphs.

`git-pkgs` embraces git as the single source of truth for releases and dependencies. With JSON config committed next to your code, reviewers and automation can see exactly which packages are in play, why they were pulled, and how to reproduce the build forever.
