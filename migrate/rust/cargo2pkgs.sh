#!/bin/bash
# Migrate a Cargo project (and its dependency graph) into a git-pkgs workspace.
# Requires: cargo, jq, git-pkgs installed.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: cargo2pkgs.sh SOURCE DEST PKG_NAME [PKG_REV]
  SOURCE   Path to Cargo project root (must contain Cargo.toml)
  DEST     Destination directory for the new git-pkgs workspace
  PKG_NAME Logical package set name for git-pkgs (used for refs and pkgs.json)
  PKG_REV  Revision tag for the root package (default: HEAD)

Environment:
  GOPROXY/GONOSUMDB/GOPRIVATE respected by go commands.
  PKGS_REF_SUFFIX / PKGS_STRIP_REF_SUFFIX honored during pkgs operations.
EOF
  exit 1
}

command -v cargo >/dev/null || { echo "cargo is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
command -v git >/dev/null || { echo "git is required" >&2; exit 1; }

[[ $# -lt 3 || $# -gt 4 ]] && usage

src=$(realpath "$1")
dst=$(realpath "$2")
root_pkg="$3"
root_rev="${4:-HEAD}"

[[ -f "$src/Cargo.toml" ]] || { echo "fatal: $src does not contain Cargo.toml" >&2; exit 1; }

mkdir -p "$dst"
if [[ ! -d "$dst/.git" ]]; then
  git init -q -b master "$dst"
fi

prefix="vendor"
strategy="max"

pkgs() {
  PKGS_REF_SUFFIX="${PKGS_REF_SUFFIX:-}" PKGS_STRIP_REF_SUFFIX="${PKGS_STRIP_REF_SUFFIX:-0}" git -C "$dst" pkgs "$@"
}

echo "[cargo2pkgs] Reading cargo metadata..."
meta=$(cd "$src" && cargo metadata --format-version 1 --locked)

# Package mapping: id -> fields
declare -A pkg_name pkg_ver pkg_dir

# Root package id
root_id=$(echo "$meta" | jq -r '.resolve.root')

# Fill package info
while IFS=$'\t' read -r id name ver manifest; do
  pkg_name["$id"]="$name"
  pkg_ver["$id"]="$ver"
  pkg_dir["$id"]="$(dirname "$manifest")"
done < <(echo "$meta" | jq -r '.packages[] | [.id,.name,.version,.manifest_path] | @tsv')

# Dependency map (id -> [dep ids])
deps_map=$(echo "$meta" | jq '.resolve.nodes | map({key:.id, value:(.deps|map(.pkg))}) | from_entries')

# Seed root pkgs.json
root_cfg="$dst/pkgs.json"
pkgs config add name "$root_pkg" >/dev/null
pkgs config add prefix "$prefix" >/dev/null
pkgs config add strategy "$strategy" >/dev/null

declare -A seen

process_module() {
  local id=$1 parent_ref=$2 parent_ver=$3 parent_cfg=$4

  [[ -n $id ]] || return
  [[ -n ${pkg_name["$id"]+x} ]] || return
  [[ -n ${seen["$id"]+x} ]] && return
  seen["$id"]=1

  local name=${pkg_name["$id"]}
  local ver=${pkg_ver["$id"]:-HEAD}
  local dir=${pkg_dir["$id"]:-}
  [[ -d "$dir" ]] || { echo "[warn] module sources missing: $dir ($name@$ver)" >&2; return; }

  # Recurse first so child configs exist before embedding.
  local parent_name=${parent_ref:-$root_pkg}
  local parent_rev=${parent_ver:-$root_rev}
  mapfile -t deps < <(echo "$deps_map" | jq -r --arg id "$id" '.[$id][]? | select(length>0)')
  for dep_id in "${deps[@]}"; do
    [[ -n $dep_id ]] || continue
    process_module "$dep_id" "$parent_name" "$parent_rev" "$root_cfg"
  done

  # Build dependencies JSON for this package.
  deps_json='{}'
  if [[ ${#deps[@]} -gt 0 ]]; then
    deps_json=$(printf '%s\n' "${deps[@]}" | while read -r dep; do
      [[ -n $dep ]] || continue
      printf '%s\t%s\n' "${pkg_name["$dep"]}" "${pkg_ver["$dep"]:-HEAD}"
    done | jq -Rs 'split("\n") | map(select(length>0) | split("\t")) | map({(.[0]):.[1]}) | add')
  fi

  config=$(jq -n --arg name "$name" --arg version "$ver" \
                 --arg prefix "$prefix" --arg strategy "$strategy" --arg url "$dir" \
                 --argjson deps "$deps_json" \
                 '{name:$name, version:$version, prefix:$prefix, strategy:$strategy, url:$url, dependencies:$deps}')

  PKGS_IMPORT_CONFIG_JSON="$config" pkgs add-dir \
    --pkg-name "$parent_name" --pkg-revision "$parent_rev" --config "$root_cfg" \
    "$name" "$ver" "$dir" >/dev/null
}

process_module "$root_id" "$root_pkg" "$root_rev" "$root_cfg"

pkgs release "$root_rev" >/dev/null

echo "[cargo2pkgs] Done."
echo "Workspace: $dst"
echo "Root package: $root_pkg @ $root_rev"
