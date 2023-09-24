# git-pkgs

> The decentralized package manager for git

> [!WARNING]
> This software is still in early development &mdash; use at your own risk!

<p align="center">
  <img src="docs/img/git-pkgs.svg" />
</p>

Decentralized package management has long been the holy grail... No, not quite. In fact decentralized package managers have acquired quite a bad reputation.

Here are some of the reasons why centrailized solutions are often preferred over decentralized ones:
- Decentralized solutions tend to pull dependencies from many different sources, with a significant loss of performance.
- Repositories that were once online may be removed or retired (or blocked by firewalls) and this may cause downloads to fail.
- While we would like a dependency to remain in a specific state, it is difficult to have this control (e.g. release tags may be tampered with).

The aim of `git-pkgs` is to overcome the above pain points and provide a robust decentralized solution that will work purely on top of git.

## Installation

### Requirements
Requires git >= 2.41
> [!NOTE]
> Be aware that this version may not yet be readily available on all platforms.

### From sources

Simply copy `git-pkgs.sh` into a folder reachable from your `$PATH`, e.g.:
```bash
cp git-pkgs.sh /usr/local/bin
```

Make sure that `git` finds it:
```
git pkgs
```

## How does it work?

`git-pkgs` is based upon the core concepts of **releases** and **dependencies**:

### Release
A release is associated with a git tag (typically a *semantic version*). The release maintains records of all dependencies of the release (these records are not stored as part of the branch itself, but as separate *git refs* that live alongside in the repository). Each dependency is based on an *orphan branch* that does not share (or pollute) the history of the main branch.

### Dependency
Dependencies are added to a release by fetching from remote repositories. Once they are added they will be committed as orphans (i.e. a single commit without a parent). Information of their source repository is maintained through their a log entry. Dependencies can be either *direct* or *transitive* (i.e. indirect).

### Conflicts
Let us consider the case where direct dependencies, e.g. `a` and `b`, require the same *transitive* dependency `c`. If `a` requires `c@1.0` and `b` requires `c@1.1` then this needs to be resolved.  Now let's also assume that we can only add dependencies one at a time (this is the effective mechanism of `git-pkgs add`).

If `a` was added before `b`, it means that we have already added the transitive dependency `c@1.0`.
When `b` is then added we have the following conflict resolution strategies:
- **max** &mdash; (default strategy) always choose the maximum version (in this case we will update from `c@1.0`to `c@1.1` when `b` is added).
- **min** &mdash; update to the minimum version (generally not a good idea).
- **keep** &mdash; we always keep the existing dependency (i.e. `c@1.0`).
- **update** &mdash; always update (when `b` is added it will update to `c@1.1`).
- **interactive** &mdash; interactive prompt where each conflict will be resolved manually.

By using the *max* strategy we should adhere to the *import compatibity rule*, which states that packages in newer versions shoud work as well as older ones (i.e. we assume that backward compatibility is maintained).

This does not necessarily mean that we use the *latest* version of a package. We will not upgrade to a newer version unless it is already required by one of the packages.

> [!NOTE]
> A default strategy can be configured through `git config pkgs.strategy <strategy>`.

### Worktrees
Packages are added through `git pkgs add`. This will effectively check out the package itself
along with any transitive dependencies (all dependencies will be fetched automatically from the remote repository,
if the dependency itself was added through `git pkgs add`).

Here is a simple example of how to add a specific revision of a remote package:
```bash
git pkgs add --prefix=pkgs github.com/foo/bar https://github.com/foo/bar 1.0
```

By running this command we will have checked out the package itself into the folder `pkgs/github.com/foo/bar` (i.e. the path is the union of the prefix and the package name). Behind the scenes, `git-pkgs` uses *git worktrees* to allow orphan branches to be checked out independently of the main branch (remember that these branches do not share any version history with the main branch; effectively we have multiple *unrelated histories* in one single git repository).

> [!NOTE]
> A default prefix path can be configured through `git config pkgs.prefix <prefix>`.

## Usage

> [!NOTE]
> In order to fully appreciate the scope and functionality of `git-pkgs`, please have a look at `test/test.sh`. This script will set up a repository `foo` and additional dependent `pkgs` repositories. Please run the script and study the resulting output.

Here follows a few examples to get you started with `git-pkgs`.

### Initializing a new package repo
We would initialize a new repository the way we normally do with `git init`:
```bash
git init [repo]
echo "pkgs" > [repo]/.gitignore
git -C [repo] branch -M main       # useful for e.g. github
```
> Note that we do not want to add the checked out packages to our main branch. If we use `pkgs` as a prefix for our packages (and as a common prefix for the worktrees) then this *must* be added to `.gitignore`.

### Adding a dependency
Dependencies are added through
```bash
git pkgs add [-s <strategy>] <pkg> <revision> [<url>]
```
with the following arguments and options:
* `pkg` &mdash; unique package identifier and worktree prefix/path.
* `url` &mdash; a git repository url.
* `revision` &mdash; a git revision (this should work also for ordinary repos that did not commit using `git pkgs release`, as long as they do not have dependencies of their own).
* `strategy` &mdash; can be `max`, `keep`, `update` or `interactive` (see section above).

### Removing a dependency
Dependencies are removed as follows:
```bash
git pkgs remove <pkg>
```
> Once a package has been removed (along with its transitive dependencies), any removed dependency may still be substituted with transitive dependencies from other packages (this will repeat the dependency resolution process that happens when a package is added).

### Creating a new release
A release records all the dependencies (and their transitive dependencies) into the git refs `refs/releases/[revision]/*`. This allows each release to be checked out again:
```bash
git pkgs release <revision>
```

### Check out a specific release
Checking out a release revision will restore all the dependencies into the state of the release in which they were recorded. We can think of this as a way to roll back dependencies to an earlier state.
```bash
git pkgs checkout <revision>
```

### Push to a remote repository
This command is useful to understand the dependencies of a specific revision (or the current one):
```bash
git pkgs push <remote> <revision>
```

### Clone from repository
Similarly to `git clone`, the following command will clone from a remote and check out the current release and its dependencies:
```bash
git pkgs clone <remote> [<directory>]
```

### Show dependency tree
This command is useful to understand the dependencies of a specific revision (or the current one):
```bash
git pkgs tree [<revision>]
```
![Example from the `foo` repository generated by `test/test.sh`](docs/img/pkgs-tree.png)

### Json export
Export dependencies to json file format. Optionally specify which revision to export.
```bash
git pkgs json-export [--all] [<revision>]
```

### Json import
Import from json. All packages are added from their source repository using `git pkgs add`.
```bash
git pkgs json-import [<filename>]
```

## Acknowledgements
Thanks to ChatGPT for providing valuable feedback. While not involved in the design per se, I very much appreciate some of the terminology used to describe this idea of mine (e.g. "decentralized dependency management").
