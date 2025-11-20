#!/bin/bash
# Migrate a Poetry-managed Python project into a git-pkgs workspace using poetry.lock for the graph.
# Requires: poetry, python3 (>=3.11 for tomllib), jq, git-pkgs.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: poetry2pkgs.sh SOURCE DEST PKG_NAME [PKG_REV]
  SOURCE   Path to project root (must contain pyproject.toml and poetry.lock)
  DEST     Destination directory for the git-pkgs workspace
  PKG_NAME Root package name (refs/pkgs/<name>/...)
  PKG_REV  Revision tag for the root package (default: HEAD)
EOF
  exit 1
}

command -v poetry >/dev/null || { echo "poetry is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }+
command -v git >/dev/null || { echo "git is required" >&2; exit 1; }

[[ $# -lt 3 || $# -gt 4 ]] && usage

src=$(realpath "$1")
dst=$(realpath "$2")
root_pkg="$3"
root_rev="${4:-HEAD}"

[[ -f "$src/pyproject.toml" && -f "$src/poetry.lock" ]] || { echo "fatal: pyproject.toml or poetry.lock missing in $src" >&2; exit 1; }

mkdir -p "$dst"
if [[ ! -d "$dst/.git" ]]; then
  git init -q -b master "$dst"
fi
if ! git -C "$dst" rev-parse -q --verify HEAD >/dev/null; then
  git -C "$dst" commit --allow-empty -q -m "poetry2pkgs init"
fi

prefix="vendor"
strategy="max"

pkgs() {
  PKGS_REF_SUFFIX="${PKGS_REF_SUFFIX:-}" PKGS_STRIP_REF_SUFFIX="${PKGS_STRIP_REF_SUFFIX:-0}" git -C "$dst" pkgs "$@"
}

tmp_env=$(mktemp -d)
trap 'rm -rf "$tmp_env"' EXIT

echo "[poetry2pkgs] Exporting lock file and installing deps..."
cd "$src"
poetry export --without-hashes --with dev -f requirements.txt -o "$tmp_env/requirements.txt"
python3 -m venv "$tmp_env/venv"
source "$tmp_env/venv/bin/activate"
pip install --quiet --upgrade pip setuptools wheel
pip install --quiet -r "$tmp_env/requirements.txt"
pip install --quiet .

echo "[poetry2pkgs] Parsing poetry.lock..."
lock_json=$(python3 - <<'PY'
import json, tomllib
from pathlib import Path
lock = tomllib.loads(Path("poetry.lock").read_text())
packages = lock.get("package", [])
out = []
for p in packages:
    deps = []
    for name, spec in (p.get("dependencies") or {}).items():
        # dependencies may be tables or strings; we just take the name
        deps.append(name)
    out.append({"name": p["name"], "version": p["version"], "deps": deps})
print(json.dumps(out))
PY
)

echo "[poetry2pkgs] Collecting installed package locations..."
installed_json=$(python3 - <<'PY'
import json, pkg_resources
data = []
for dist in pkg_resources.working_set:
    if dist.key in {"pip","setuptools","wheel"}:
        continue
    data.append({"key": dist.key, "name": dist.project_name, "version": dist.version, "location": dist.location})
print(json.dumps(data))
PY
)

# Build maps: name(lower) -> info
declare -A lock_ver lock_deps name_canon
while IFS=$'\t' read -r name ver deps_json; do
  key=${name,,}
  lock_ver["$key"]="$ver"
  lock_deps["$key"]="$deps_json"
  name_canon["$key"]="$name"
done < <(echo "$lock_json" | jq -r '.[] | [.name,.version, (.deps|join(" "))] | @tsv')

# Determine root package name/version via poetry.
root_name=$(poetry version | awk '{print $1}')
root_version=$(poetry version | awk '{print $2}')

lock_ver["$root_name"]="$root_version"
lock_deps["$root_name"]=$(poetry show -T | awk '{print $1}')

# Map installed packages for quick lookup.
declare -A inst_dir inst_ver
while IFS=$'\t' read -r key name ver loc; do
  inst_ver["$key"]="$ver"
  inst_dir["$key"]="$loc"
  name_canon["$key"]="$name"
done < <(echo "$installed_json" | jq -r '.[] | [.key,.name,.version,.location] | @tsv')

root_cfg="$dst/pkgs.json"
pkgs config add name "$root_pkg" >/dev/null
pkgs config add prefix "$prefix" >/dev/null
pkgs config add strategy "$strategy" >/dev/null

process_pkg() {
  local key=$1 parent_ref=$2 parent_ver=$3 parent_cfg=$4

  [[ -n $key ]] || return
  [[ -n ${lock_ver[$key]+x} ]] || { echo "[skip] no lock entry for $key" >&2; return 0; }

  local name=${name_canon[$key]:-$key}
  local ver=${lock_ver[$key]}
  local dir_base=${inst_dir[$key]:-}
  local dir="$dir_base/$name"

  if [[ ! -d "$dir" ]]; then
    # Fallback to base location.
    dir="$dir_base"
  fi
  [[ -d "$dir" ]] || { echo "[warn] package dir missing: $dir ($name==$ver)" >&2; return 0; }

  local this_cfg="$dst/$prefix/$name/pkgs.json"
  mkdir -p "$(dirname "$this_cfg")"

  # Recurse into lock deps.
  if [[ -n ${lock_deps[$key]:-} ]]; then
    for dep in ${lock_deps[$key]}; do
      depkey=${dep,,}
      process_pkg "$depkey" "$name" "$ver" "$this_cfg"
    done
  fi

  # Build deps json for this package based on lock deps.
  deps_json="{}"
  if [[ -n ${lock_deps[$key]:-} ]]; then
    deps_json="{"
    first=1
    for dep in ${lock_deps[$key]}; do
      depkey=${dep,,}
      [[ -n ${lock_ver[$depkey]+x} ]] || continue
      [[ $first -eq 0 ]] && deps_json+=","
      deps_json+="\"${name_canon[$depkey]:-$dep}\":\"${lock_ver[$depkey]}\""
      first=0
    done
    deps_json+="}"
  fi

  # Clean worktree path to avoid conflicts.
  rm -rf "$dst/$prefix/$name"
  mkdir -p "$(dirname "$parent_cfg")"

  config=$(jq -n --arg name "$name" --arg version "$ver" \
                 --arg prefix "$prefix" --arg strategy "$strategy" --arg url "$dir" \
                 --argjson deps "${deps_json:-'{}'}" \
                 '{name:$name, version:$version, prefix:$prefix, strategy:$strategy, url:$url, dependencies:$deps}')

  PKGS_IMPORT_CONFIG_JSON="$config" PKGS_DEFAULT_PREFIX="$prefix" pkgs add-dir \
    --pkg-name "$parent_ref" --pkg-revision "$parent_ver" --config "$parent_cfg" \
    "$name" "$ver" "$dir" >/dev/null
}

# Find root key and start.
root_key=${root_name,,}

process_pkg "$root_key" "$root_pkg" "$root_rev" "$root_cfg"

echo "[poetry2pkgs] Done."
echo "Workspace: $dst"
echo "Root package: $root_pkg @ $root_rev"
