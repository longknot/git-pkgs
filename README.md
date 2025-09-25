# git-pkgs — the git-native, serverless package manager

<p align="center">
  <img src="docs/img/git-pkgs.svg" />
</p>

`git-pkgs` lets any git repository double as its own package registry. Every release, dependency, and provenance record is tracked with stock git features—no central service, daemon, or database required. The result is a *git-native* and genuinely *serverless* dependency workflow that stays portable, auditable, and reproducible across teams.

## Why git-pkgs?
- **Self-hosted without servers** — Dependencies live under `refs/pkgs/` inside the same repo; mirroring your repository also preserves its package history.
- **One repository, many packages** — Orphan branches and worktrees keep package sources alongside your project while isolating their histories.
- **Deterministic releases** — `git pkgs release` records the exact tree of direct and transitive dependencies, so future checkouts reproduce the same stack.
- **Security & provenance** — Dependencies are pulled from trusted remotes once, then frozen inside your repo, protecting you from disappearing registries or tampered tags.
- **Language-agnostic** — Works equally well for Go, Python, Rust, firmware blobs, or even custom build artifacts because everything is just git objects.

## Core concepts
- **Releases** — A release is a git tag that has an accompanying `refs/pkgs/<name>/<tag>/` namespace. That namespace stores the full dependency graph for that snapshot, plus metadata trailers (name, type, source URL, revision).
- **Dependencies** — Added via `git pkgs add`, each dependency is fetched once, committed as an orphan branch, and referenced through logs that retain its upstream origin.
- **Worktrees** — Packages appear in a configurable prefix (default `pkgs/`). They are checked out via git worktrees, so the main project history stays untouched.
- **Conflict strategies** — When two packages request different revisions of the same dependency, strategies like `max`, `keep`, `update`, `min`, and `interactive` decide how to reconcile them.

## Compared to language-specific package managers
| Topic | Typical language manager | `git-pkgs` |
| ----- | ------------------------ | ---------- |
| Registry | Central service (npm, crates.io) | None. Uses any git remote or local path |
| Availability | Registry downtime blocks installs | As long as you can run git, you can fetch dependencies |
| Scope | Tied to one language/runtime | Works with anything representable in git |
| Provenance | Trusts published tarballs | Trusts git commits that you audit and freeze |
| Vendoring | Often requires extra tooling | Built-in via orphan branches and worktrees |
| Air-gapped builds | Requires mirrors or proxies | `git clone` your repo; dependencies are already there |
| Automation | Language-specific CLIs or APIs | Pure git + optional JSON-RPC (`git pkgs mcp`) |

## Quick start
```bash
# Install (anywhere on PATH)
cp git-pkgs.sh /usr/local/bin/git-pkgs

# Verify availability
git pkgs --help

# Initialize a project repo
mkdir demo && cd demo
git init

echo "pkgs" > .gitignore          # keep worktrees out of the main branch
git config pkgs.name demo         # required: identifies this package set

# Optional defaults
git config pkgs.prefix pkgs       # where worktrees for deps will live
git config pkgs.strategy max      # conflict resolution policy

# Add a dependency from a remote repo
git pkgs add github.com/example/lib v1.2.3 https://github.com/example/lib

# Record a release of the current project + deps
git commit -am "Initial commit"
git tag v1.0.0
git pkgs release -m "demo v1.0.0" v1.0.0

# Rehydrate later (anywhere you can run git)
git pkgs checkout v1.0.0
```

Because dependencies live in orphan branches and are accessed through worktrees, the main project history remains linear and clean. You can still use your normal branching model, pull requests, and review workflows while benefiting from embedded dependencies.

## Configuration surface
- `pkgs.name` *(required)* — Logical package name used to namespace refs (often the repo name).
- `pkgs.prefix` *(optional)* — Filesystem prefix where dependency worktrees are checked out (`pkgs/` by convention).
- `pkgs.url` *(optional)* — Repository URL recorded in release metadata; defaults to `remote.origin.url`.
- `pkgs.type` *(optional)* — Free-form type label stored with releases. Defaults to `${PKGS_DEFAULT_TYPE:-pkg}`.
- `pkgs.strategy` *(optional)* — Default conflict strategy (`max`, `min`, `keep`, `update`, `interactive`). Defaults to `${PKGS_DEFAULT_STRATEGY:-max}`.
- Environment overrides — `PKGS_DEFAULT_TYPE`, `PKGS_DEFAULT_STRATEGY`, and `PKGS_DEFAULT_PREFIX` let you set fallbacks before running the command.

## Command reference
Each command is implemented in `git-pkgs.sh`; the highlights below reflect its behavior.

- `git pkgs add [-s <strategy>] [-P <prefix>] <pkg> <revision> [<remote>]`
  - Fetches dependency refs from the remote, converts the requested revision into an orphan branch, and pulls referenced packages into `refs/pkgs/<pkg_name>/HEAD/`. If `<remote>` is omitted, the last recorded source URL is reused.
  - Prints `[add]`, `[update]`, or `[keep]` decisions for each dependency. `--strategy` controls conflict handling.
- `git pkgs remove [-P <prefix>] <pkg>`
  - Only removes direct dependencies (those not required transitively). Cleans the worktree, deletes the HEAD ref, and attempts to resolve downstream packages by reusing other roots.
- `git pkgs release [-m <message>] <revision>`
  - Commits trailers describing the release, tags the repository, snapshots all current dependencies into `refs/pkgs/<name>/<revision>/`, and re-orphanizes the package branch.
- `git pkgs checkout [-P <prefix>] <revision>`
  - Checks out the project tag and re-creates the dependency worktrees (removing any stale ones). Works with any recorded release or `HEAD`.
- `git pkgs fetch [--all] <remote> [<revision>]`
  - Imports release metadata and tags from another repo. With `--all` it mirrors every package ref; otherwise supply a `<revision>` to fetch that specific release.
- `git pkgs push <remote> [<revision>]`
  - Forces a push of the current branch, the given revision tag (defaults to latest tag by `git describe`), and all `refs/pkgs/*` namespaces.
- `git pkgs pull <remote> [<revision>]`
  - Convenience wrapper that fetches metadata from the remote and immediately runs `git pkgs checkout`.
- `git pkgs clone <remote> [<directory> [<revision>]]`
  - Clones a repository, configures `pkgs.name` from the release metadata, fetches dependency refs, and checks them out locally.
- `git pkgs ls-releases <pkg>`
  - Lists tags for a dependency package by querying the stored source URL.
- `git pkgs status [<revision>]`
  - Shows `commit` and `name@revision` for each dependency currently referenced in HEAD (the optional revision argument is reserved for future extensions).
- `git pkgs tree [-d <depth>] [--all] [<revision>]`
  - Produces an ASCII dependency tree with glyphs and colors (✓ for locked nodes, • for transitive branches). `--all` walks every release root; otherwise it focuses on the selected package. Depth defaults to unlimited.
- `git pkgs show <pkg>`
  - Presents colorized metadata (versions, authorship, source URL) and lists both direct and indirect dependencies for a package.
- `git pkgs json-export [--all] [<revision>]`
  - Emits a JSON manifest containing the project name, revision, and dependency metadata (including source URL and commit). `--all` includes transitive dependencies.
- `git pkgs json-import [<filename>]`
  - Reads a manifest (or stdin) and replays `git pkgs add` for each entry, effectively re-hydrating a dependency set from JSON. Requires `jq`.
- `git pkgs prune`
  - Runs `git gc` with aggressive settings to clean up unreachable objects created by orphan branches.
- `git pkgs mcp`
  - Starts a JSON-RPC transport that exposes git-pkgs commands as structured tools. Useful for editor integrations, automation runtimes, or AI assistants.

> Tip: all commands (except `clone` and `mcp`) require a working tree and leverage `git-sh-setup` for consistent error handling.

## Migration guide: adopting a git-pkgs workflow
1. **Pick a package prefix.** Decide where dependencies should live (e.g. `pkgs/`). Add that directory to `.gitignore` so checkout worktrees do not pollute your main tree.
2. **Configure package identity.** Set `git config pkgs.name <your-name>` and optional defaults (`pkgs.prefix`, `pkgs.strategy`) before importing dependencies.
3. **Import existing dependencies.** For each direct dependency, run `git pkgs add`. Target specific tags, commits, or branches; transitive dependencies resolve automatically.
4. **Capture the baseline.** Tag your project and run `git pkgs release <tag>`. This writes dependency metadata into `refs/pkgs/<name>/<tag>/` without touching your working tree.
5. **Clean up legacy vendoring.** Remove manual vendored copies or lockfiles you no longer need; the dependency state now lives in git itself.
6. **Educate contributors.** Share the new commands (`add`, `remove`, `tree`, `checkout`, `status`) and the conflict strategy you prefer. Contributors need nothing beyond git and the `git-pkgs` script.
7. **Integrate into CI.** Replace package install steps with `git pkgs checkout <revision>` after cloning the repo. Builds now depend only on git availability.

## Advanced usage patterns
- **Mirror mode** — Use `git pkgs push` so collaborators and CI servers receive dependency refs alongside code.
- **Offline bootstrap** — Combine `git pkgs clone` with intra-company Git servers to provision air-gapped machines.
- **Audit trails** — `git pkgs show` and `git pkgs status` give precise provenance for each dependency, including author and upstream revision.
- **Bulk updates** — With the `update` strategy or by re-running `git pkgs add` at a new revision, you can coordinate dependency upgrades in a controlled, reviewable fashion.
- **Machine integrations** — The `mcp` command provides structured command metadata, enabling IDEs, bots, or policy engines to call git-pkgs declaratively.

## Thinking ahead: potential of git-native dependencies
- **Resilience** — Every clone becomes a full mirror of your dependency universe. No single registry outage can halt builds.
- **Composable repos** — Teams can share modular components simply by granting git access. Any repository can be a package repository without extra infrastructure.
- **Policy enforcement** — Because releases are pure git data, you can sign tags, run policy checks, or enforce review gates before `git pkgs release` is allowed.
- **Long-term archival** — Archiving your repository (e.g. to object storage) preserves complete dependency provenance for future rebuilds and audits.

## Further resources
- `docs/` — Additional diagrams, examples, and CLI reference material.
- `docs/mcp.md` — Configuring mcp clients to use git-pkgs.
- `test/test.sh` — End-to-end demo that sets up nested repos to show how `git-pkgs` resolves dependency trees.

`git-pkgs` shows what happens when package management fully embraces git: a single tool, one distributed source of truth, and dependency management that is as portable as a bare repository.
