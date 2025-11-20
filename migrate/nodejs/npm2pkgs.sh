#!/bin/bash

# Add nodejs to git-pkgs repository.
function add_to_registry() {
  local name=$1
  local version=$2
  local parent_name=$3
  local parent_version=$4
  local pkgs_config=$5

  git -C "$node_modules/$name" add .
  # git -C "$node_modules/$name" pkgs config add name $name
  # git -C "$node_modules/$name" pkgs config add prefix node_modules
  # if ! git -C "$node_modules/$name" show-ref -q $version; then
  git -C "$node_modules/$name" pkgs release $version
  #fi
  git -C $dst_path pkgs add --pkg-name $parent_name --pkg-revision $parent_version \
    --config $pkgs_config $name $version $node_modules/$name
}

# Recurse through dependency tree.
function recurse() {
  local dependencies="$1.dependencies"
  local parent_name=$2
  local parent_version=$3
  local pkgs_config=$4

  echo $json | jq -r "$dependencies|keys_unsorted[]" 2> /dev/null |
		while read name; do
      local version=$(echo $json | jq -r "$dependencies.\"$name\".version")

      git init -q -b master "$node_modules/$name"
      git -C "$node_modules/$name" pkgs config add name $name
      git -C "$node_modules/$name" pkgs config add prefix node_modules

      # Add sub-dependencies first so that all dependencies are added to pkgs.json of parent.
      recurse "$dependencies.\"$name\"" "$name" "$version" "$node_modules/$name/pkgs.json"
      # Now add (and orphanize) parent package.
      add_to_registry "$name" "$version" "$parent_name" "$parent_version" "$pkgs_config"
		done
}

if [[ $# != 3 ]]; then
  echo "Usage: npm2pkgs SOURCE DEST NAME"
  echo "  SOURCE = source folder of nodejs project"
  echo "  DEST   = destination folder of git-pkgs project"
  echo "  NAME   = name of git-pkgs project"
  exit
fi

src_path=$(realpath $1)
dst_path=$(realpath $2)
node_modules="$src_path/node_modules"
project_name=$3

git init -b master $dst_path
git -C $dst_path pkgs config add name $project_name
git -C $dst_path pkgs config add prefix node_modules
echo "node_modules" > "$dst_path/.gitignore"

# Read dependency tree from npm.
json=$(cd $src_path && npm ls -a --omit dev --json)

# Add dependencies.
recurse "" "$project_name" HEAD "pkgs.json"
