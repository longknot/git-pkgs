#!/bin/bash
# Convert a Go module (and its dependency graph) into a git-pkgs workspace
# without mutating the Go module cache. Requires: go, jq, git pkgs.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: go2pkgs.sh [--vendor-only] SOURCE DEST PKG_NAME [PKG_REV]
  SOURCE       Path to Go module root (must contain go.mod)
  DEST         Destination directory for the new git-pkgs workspace
  PKG_NAME     Logical package set name for git-pkgs (used for refs and pkgs.json)
  PKG_REV      Revision tag for the root package (default: HEAD)

Options:
  --vendor-only   Import only modules reachable in the package import graph for this platform (similar to `go mod vendor`).

Environment:
  GOPROXY/GONOSUMDB/GOPRIVATE respected by go commands.
EOF
  exit 1
}

command -v go >/dev/null || { echo "go is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
command -v git >/dev/null || { echo "git is required" >&2; exit 1; }

vendor_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vendor-only) vendor_only=1; shift ;;
    *) break ;;
  esac
done

[[ $# -lt 3 || $# -gt 4 ]] && usage

src=$(realpath "$1")
dst=$(realpath "$2")
root_pkg="$3"
root_rev="${4:-}"

[[ -f "$src/go.mod" ]] || { echo "fatal: $src does not contain go.mod" >&2; exit 1; }

gomodcache=$(go env GOMODCACHE)

mkdir -p "$dst"
if [[ ! -d "$dst/.git" ]]; then
  git init -q -b master "$dst"
fi

prefix="vendor"
strategy="max"
ref_suffix="/PKG"
strip_suffix=1

pkgs() {
  PKGS_REF_SUFFIX="$ref_suffix" PKGS_STRIP_REF_SUFFIX="$strip_suffix" git -C "$dst" pkgs "$@"
}

# Fetch module graph locally.
echo "[go2pkgs] Downloading modules..."
(cd "$src" && go mod download all >/dev/null)

echo "[go2pkgs] Reading module metadata..."
mods=$(cd "$src" && go list -m -json all | jq -s '.') || { echo "fatal: go list -m -json all failed" >&2; exit 1; }
if [[ $vendor_only -eq 1 ]]; then
  echo "[go2pkgs] Restricting to vendor-only module set (import graph)..."
  pkg_mods=$(cd "$src" && go list -deps -test -json ./... | jq -r 'select(.Module)|.Module.Path' | sort -u)
  graph=$(cd "$src" && go mod graph | awk 'NR==1{print;stderr="";next} {print}' )
else
  graph=$(cd "$src" && go mod graph)
  pkg_mods=
fi

root_mod=$(echo "$mods" | jq -r '.[] | select(.Main==true).Path')
[[ -n "$root_mod" ]] || { echo "fatal: could not determine main module" >&2; exit 1; }

declare -A mod_version mod_dir mod_deps

while IFS=$'\t' read -r path ver dir repldir; do
  [[ -n "$path" ]] || continue
  v=${ver:-HEAD}
  d=${repldir:-$dir}
  [[ -z "$d" ]] && d="$gomodcache/$path@$v"
  mod_version["$path"]=$v
  mod_dir["$path"]=$d
done < <(echo "$mods" | jq -r '.[] | [ .Path, (.Version // "HEAD"), (.Dir // ""), (if .Replace and .Replace.Dir then .Replace.Dir else "" end) ] | @tsv')

# Optional pruning of modules to those present in the import graph.
if [[ $vendor_only -eq 1 ]]; then
  declare -A keep
  for m in $pkg_mods; do keep["$m"]=1; done
  for m in "${!mod_version[@]}"; do
    if [[ -z ${keep[$m]+x} ]]; then
      unset mod_version["$m"]
      unset mod_dir["$m"]
      unset mod_deps["$m"]
    fi
  done
fi

if [[ -z "$root_rev" ]]; then
  guess=${mod_version[$root_mod]:-}
  root_rev=${guess:-HEAD}
fi

parse_modver() {
  local token=$1
  if [[ "$token" == *"@"* ]]; then
    echo "${token%@*}" "${token##*@}"
  else
    echo "$token" ""
  fi
}

while read -r parent child; do
  [[ -n "$parent" && -n "$child" ]] || continue
  read -r ppath _ <<<"$(parse_modver "$parent")"
  read -r cpath _ <<<"$(parse_modver "$child")"
  mod_deps["$ppath"]="${mod_deps[$ppath]:-} $cpath"
done <<< "$graph"

cfg_dir=$(mktemp -d)
cleanup() { rm -rf "$cfg_dir"; }
trap cleanup EXIT

cfg_path() {
  local mod=$1
  echo "$cfg_dir/$(echo "$mod" | tr '/:@' '___').json"
}

write_config() {
  local mod=$1
  local ver=${mod_version[$mod]:-HEAD}
  local url=${mod_dir[$mod]}
  local deps_raw="${mod_deps[$mod]:-}"
  local deps="{}"
  for dep in $deps_raw; do
    if [[ "$dep" == "go" ]]; then
      continue
    fi
    local dv=${mod_version[$dep]:-HEAD}
    deps=$(printf '%s\n' "$deps" | jq --arg k "${dep}${ref_suffix}" --arg v "$dv" '. + {($k):$v}')
  done
  local cfg
  cfg=$(jq -n --arg name "${mod}${ref_suffix}" --arg version "$ver" \
               --arg prefix "$prefix" --arg strategy "$strategy" --arg url "$url" \
               --argjson deps "$deps" \
               '{name:$name, version:$version, prefix:$prefix, strategy:$strategy, url:$url, dependencies:$deps}')
  local path
  path=$(cfg_path "$mod")
  printf '%s\n' "$cfg" > "$path"
  echo "$path"
}

for mod in "${!mod_version[@]}"; do
  write_config "$mod" >/dev/null
done

# Seed root pkgs.json.
root_cfg="$dst/pkgs.json"
cp "$(cfg_path "$root_mod")" "$root_cfg"
pkgs config add name "$root_pkg" >/dev/null
pkgs config add prefix "$prefix" >/dev/null
pkgs config add strategy "$strategy" >/dev/null
pkgs config add refSuffix "$ref_suffix" >/dev/null

process_module() {
  local mod=$1 parent_ref=$2 parent_ver=$3 parent_cfg=$4
  [[ -n ${mod_version[$mod]+x} ]] || return
  local ver=${mod_version[$mod]:-HEAD}
  local dir=${mod_dir[$mod]:-}
  if [[ -z "$dir" ]]; then
    dir="$gomodcache/$mod@$ver"
  fi

  # Skip pseudo modules (e.g., the stdlib "go") or missing source dirs.
  if [[ "$mod" == "go" ]]; then
    seen[$mod]=1
    return
  fi

  local cfg=$(cfg_path "$mod")

  [[ -d "$dir" ]] || { echo "[warn] module sources missing: $dir ($mod@$ver)" >&2; return; }
  [[ -n ${seen[$mod]+x} ]] && return
  seen[$mod]=1

  # Recurse first so child configs exist before embedding.
  local mod_ref="${mod}${ref_suffix}"
  local child_parent_ref=${parent_ref:-$root_pkg}
  local child_parent_ver=${parent_ver:-$root_rev}
  for dep in ${mod_deps[$mod]:-}; do
    [[ -n ${mod_version[$dep]+x} ]] || continue
    process_module "$dep" "$child_parent_ref" "$child_parent_ver" "$cfg"
  done

  local env_cfg
  env_cfg=$(cat "$cfg")

  # Ensure clean worktree path to avoid pkgs.json overwrite errors.
  local worktree_path="$dst/$prefix/$mod"
  if [[ $strip_suffix != 0 && -n $ref_suffix && $mod == *"$ref_suffix" ]]; then
    worktree_path="${worktree_path%$ref_suffix}"
  fi
  rm -rf "$worktree_path"

  local name_flags=(--config "$root_cfg")
  if [[ -n "$parent_ref" ]]; then
    name_flags=(--pkg-name "$parent_ref" --pkg-revision "$parent_ver" --config "$parent_cfg")
  fi

  echo "[go2pkgs] Importing module: $mod @$ver ..."
  PKGS_IMPORT_CONFIG_JSON="$env_cfg" pkgs add-dir \
    "${name_flags[@]}" \
    "$mod_ref" "$ver" "$dir" >/dev/null
}

declare -A seen
process_module "$root_mod" "$root_pkg" "$root_rev" "$root_cfg"

pkgs release "$root_rev" >/dev/null

echo "[go2pkgs] Done."
echo "Workspace: $dst"
echo "Root package: $root_pkg ($root_mod) @ $root_rev"
