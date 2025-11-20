#!/bin/bash
#
# git-pkgs.sh: the decentralized package manager for git.
#
# Copyright (c) 2025 Mattias Andersson <mattias@longknot.com>.

if [ $# -eq 0 ]; then
  set -- -h
fi

MIN_GIT_VERSION="2.41"
PKGS_DEFAULT_PREFIX=${PKGS_DEFAULT_PREFIX:-"pkgs"}
PKGS_DEFAULT_REVISION=${PKGS_DEFAULT_REVISION:-"HEAD"}
PKGS_DEFAULT_TYPE=${PKGS_DEFAULT_TYPE:-"pkg"}
PKGS_DEFAULT_STRATEGY=${PKGS_DEFAULT_STRATEGY:-"max"}
GIT_PKGS_JSON=${GIT_PKGS_JSON:-'pkgs.json'}
CONFIG_CHANGED=0

OPTS_SPEC="\
git pkgs release [-m <message>] <revision>
git pkgs add [-s <strategy>] [-P <prefix>] <pkg> <revision> [<remote>]
git pkgs remove [-P <prefix>] <pkg>
git pkgs checkout [-P <prefix>] <revision>
git pkgs fetch [--all] <remote> [<revision>]
git pkgs push <remote> [<revision>]
git pkgs pull <remote> [<revision>]
git pkgs clone <remote> [<directory> [<revision>]]
git pkgs ls-releases <pkg>
git pkgs status [<revision>]
git pkgs tree [--depth <depth>] [--all] [<revision>]
git pkgs add-dir [-n <namespace>] <pkg> <revision> <path>
git pkgs show <pkg>
git pkgs json-import [<filename>]
git pkgs json-export [--all] [<revision>]
git pkgs mcp
git pkgs config [add|remove|list]
--
h,help        show the help
q             quiet
d,debug       show debug info
P,prefix=     prefix
m,message=    commit message
c,config=     path of config file
s,strategy=   conflict resolution strategy ('max', 'min', 'keep', 'update', 'interactive')
all           include all dependencies in an export (both direct and transitive).
pkg-name=     package name (optional)
pkg-revision= package revision (optional)
pkg-type=     package type (optional)
pkg-url=      package url (optional)
n,namespace=  package namespace (optional)
depth=        recursion depth
"

PKGS_KEYS='["name","description","version","author","authors","contributors","license","repository","url","homepage","funding","prefix","dependencies","paths","engines","files","config","extra","scripts"]'

eval "$(echo "$OPTS_SPEC" | git rev-parse --parseopt -- "$@" || echo exit $?)"

die() {
    printf '%s\n' "$1" >&2
    exit "${2-1}"
}

# Config manipulation with jq.
config_read() {
	if [ -f "$pkg_config_file" ]; then
		cat "$pkg_config_file"
		exit
	fi
	echo '{}'
}

config_write() {
	if [ $CONFIG_CHANGED ]; then
		dependencies=$(echo $config | \
			jq '.dependencies//empty|to_entries|map(.+{namespaced:(.key|contains(":"))})|sort_by(.namespaced,.key)|from_entries')
		config=$(jq -n --argjson k "$PKGS_KEYS" --argjson c "$config" --argjson d "${dependencies:-null}" \
     '[($k|map({(.):null})|add),$c]|add|.dependencies=$d|with_entries(select(.value!=null))')
		echo "$config" > "$pkg_config_file"
	fi
}

config_get() {
	key=$1
	echo "$config" | jq -r ".$key//empty"
}

config_set() {
	CONFIG_CHANGED=1
	key=$1;	value=$2
	config=$(echo $config | jq ".$key=$value")
}

config_set_str() {
	config_set "$1" "\"$2\""
}

add_pkgs_dependencies() {
	json_name=$name
	if [[ $namespace ]]; then
		json_name="$namespace:$name"
	fi
	config_set_str "dependencies.\"$json_name\"" "$revision"
}

get_dependencies() {
	echo "$config" | jq -r '.dependencies//empty|to_entries[]|flatten|@tsv'
}

get_paths() {
	echo "$config" | jq -r '.paths//empty|to_entries[]|flatten|@tsv'
}

pkg_config_file="$GIT_PKGS_JSON"
message=
all=
depth=-1

while [ $# -gt 0 ]; do
	opt="$1"
	shift
	case "$opt" in
		-q) quiet=1 ;;
		-d) DEBUG=1 ;;
	  -c) pkg_config_file="$1"; shift;;
		-P) prefix="$1"; shift;;
		-m) message="$1"; shift;;
		-s) strategy="$1"; shift;;
		--depth) depth="$1"; shift;;
		-n) namespace="$1"; shift;;
		--all) all=1 ;;
		--pkg-name) pkg_name="$1"; shift;;
		--pkg-revision) pkg_revision="$1"; shift;;
		--pkg-url) pkg_url="$1"; shift;;
		--pkg-type) pkg_type="$1"; shift;;
		--) break ;;
		*) die "Unexpected option: $opt" ;;
	esac
done

command="$1"
shift

config="$(config_read)"

: "${pkg_revision:=$PKGS_DEFAULT_REVISION}"

: "${pkg_name:=$(config_get 'name')}"

: "${pkg_type:=$(config_get 'type')}"
: "${pkg_type:=$PKGS_DEFAULT_TYPE}"

: "${prefix:=$(config_get 'prefix')}"
: "${prefix:=$PKGS_DEFAULT_PREFIX}"

: "${strategy:=$(config_get 'strategy')}"
: "${strategy:=$PKGS_DEFAULT_STRATEGY}"

: "${pkg_url:=$(config_get 'url')}"
: "${pkg_url:=$(git config --get remote.origin.url)}"

: "${pkg_ref_suffix:=$(config_get 'refSuffix')}"
: "${pkg_ref_suffix:=$PKGS_REF_SUFFIX}"

if [[ -n $DEBUG ]]; then
	echo "[DEBUG] name        : $pkg_name"
	echo "[DEBUG] revision    : $pkg_revision"
	echo "[DEBUG] prefix      : $prefix"
	echo "[DEBUG] type        : $pkg_type"
	echo "[DEBUG] strategy    : $strategy"
	echo "[DEBUG] url         : $pkg_url"
	echo "[DEBUG] config_file : $pkg_config_file"
	echo "[DEBUG] command     : $command"
fi


# Check git version requirements.
require_git_version() {
	(echo min version $MIN_GIT_VERSION; git --version) | sort -Vk3 | tail -1 | grep -q git \
	  || die "git-pkgs requires git version $MIN_GIT_VERSION"
}

# Read char function that works with both bash and zsh.
read_char() {
  stty -icanon -echo
  REPLY=$(dd bs=1 count=1 2>/dev/null)
  stty icanon echo
}

sort_revisions() {
	printf "%s\n" $@ | sort -V
}

min_revision() {
	sort_revisions $@ | head -1
}

max_revision() {
	sort_revisions $@ | tail -1
}

get_trailer() {
	git -P show -s --pretty="%(trailers:key=$2,valueonly)%-" $1
}

ref_exists() {
	git show-ref -q $1
}

get_revision() {
	git describe --tags --abbrev=0
}

get_commit() {
	git rev-parse "$1" 2> /dev/null
}

ref_pattern_match() {
	ref_pattern="$1"
	ref_match="$2"
	git for-each-ref "$ref_pattern" --format="%(refname)" | grep -q "^$ref_match$"
}

# Hackish, but it works.
is_non_transitive() {
	git name-rev --no-undefined --refs="refs/pkgs/$1/*/$1" "refs/pkgs/$pkg_name/HEAD/$1" &> /dev/null
}

# Check if two refs are equal.
refs_equal() {
	[[ $(get_commit "$1") == $(get_commit "$2") ]]
}


pkg_path() {
	pkg_ref=$1          # package name as stored in refs
	pkg=$pkg_ref        # package name as used for worktrees (may be stripped)

	# Optionally strip a constant ref leaf (e.g., "/PKG") when mapping to worktree paths.
	pkg=${pkg%"$pkg_ref_suffix"}

	pkg_paths=$(get_paths)

	if [[ -z $pkg_paths ]]; then
		echo "$prefix/$pkg"
		exit
	fi

	echo "$pkg_paths" |
		while read pattern prefix; do
			# Extract namespace from pattern.
			pattern_path=$(echo $pattern|sed 's/.*://g')
			pattern_ns=${pattern%":$pattern_path"}
			pkg_path=$pkg
			if [[ $pattern_path != $pattern_ns ]]; then
				pattern="$pattern_ns/$pattern_path"
				pkg_path=${pkg_path#"$pattern_ns/"}
			fi

			# Q: pattern = "dev:..." --> "HEAD/@dev/..." ?
				if ref_pattern_match "refs/pkgs/$pkg_name/HEAD/$pattern" "refs/pkgs/$pkg_name/$pkg_revision/$pkg_ref"; then
					if [[ $prefix != "false" ]]; then
						echo "$prefix/$pkg_path"
						exit
					fi
				fi
		done
}

pkg_path2() {
	pkg=$1
	pkg_paths=$(get_paths)

	echo "pkg_paths = $pkg_paths"
	echo "prefix = $prefix"
	echo "pkg = $pkg"

	if [[ -z $pkg_paths ]]; then
		echo "$prefix/$pkg"
		exit
	fi

	echo "$pkg_paths" |
		while read pattern prefix; do
			# Extract namespace from pattern.
			pattern_path=$(echo $pattern|sed 's/.*://g')
			pattern_ns=${pattern%":$pattern_path"}
			pkg_path=$pkg
			if [[ $pattern_path != $pattern_ns ]]; then
				pattern="$pattern_ns/$pattern_path"
				pkg_path=${pkg_path#"$pattern_ns/"}
			fi
			echo "* pkg_revision = $pkg_revision"
			echo "* pattern_path = $pattern_path, pattern_ns = $pattern_ns, pattern = $pattern, pkg_path = $pkg_path"
			echo "* refs/pkgs/$pkg_name/HEAD/$pattern refs/pkgs/$pkg_name/$pkg_revision/$pkg"

			# Q: pattern = "dev:..." --> "HEAD/@dev/..." ?
			if ref_pattern_match "refs/pkgs/$pkg_name/$pkg_revision/$pattern" "refs/pkgs/$pkg_name/$pkg_revision/$pkg"; then
				if [[ $prefix != "false" ]]; then
					echo "$prefix/$pkg_path"
					exit
				fi
			fi
		done
}


# Remove existing worktree.
worktree_reset() {
	path=$(pkg_path $1)
	if [ -d "$path" ]; then
   	git worktree remove -f "$path"
		git worktree prune
	fi
}

# If pkg exists, use "git checkout", otherwise "git worktree add".
worktree_checkout() {
	echo "Checking out $pkg"
	path=$(pkg_path $pkg)

	if [[ ! -z $path ]]; then
		if [ -d $path ]; then
			git -C $path checkout -q "$target"
		else
			git worktree add -q -f $path "$target"
		fi
	fi
}

# Extract trailers for 'git for-each-ref'.
trailers() {
	printf "%%(contents:trailers:"
	for key in $@; do
		printf "key=$key,"
	done
	printf "valueonly,separator=|)"
}

check_pkg_name() {
	if [[ ! $pkg_name ]]; then
		echo 'fatal: package does not have a name.'
		echo 'Configure a package name like this:'
		echo "'git pkgs config name <name>'"
		die
	fi
}

# Make branch an orphan.
orphanize() {
	target="refs/pkgs/$name/$revision/$name"

	commit=$(git rev-parse $target)

	worktree_reset $name

	path=$(pkg_path $name)

	git worktree add -q --no-checkout $path $target

	git -C "$path" checkout -q -f --orphan "$name"
	git -C "$path" status

	git -C "$path" -c trailer.ifexists=addIfDifferent commit -C $target -q \
		--trailer "git-pkgs-name:$name" \
		--trailer "git-pkgs-type:$pkg_type" \
		--trailer "git-pkgs-revision:$revision" \
		--trailer "git-pkgs-commit:$commit" \
		--trailer "git-pkgs-url:$url"

	git update-ref -d $target
	git fetch -q . "refs/heads/$name:$target" --no-tags --force
	git update-ref -d "refs/heads/$name"
}

add_package() {
	if [[ $rev_a == $rev ]]
	then
		echo " * [keep]            $pkg@$rev"
	else
		if [[ -z $rev_a ]]; then
			echo " * [add]             $pkg@$rev"
		else
			echo " * [update]          $pkg@$rev_a -> $pkg@$rev"
		fi
		git update-ref "$target" "refs/$incoming"
		worktree_reset $pkg
		worktree_checkout $pkg
	fi
}

# Resolve transitive dependency.
resolve_transitive_dependency() {
	a=$1
	b=$2
	target=$3

	pkg=${target#"refs/pkgs/$pkg_name/$pkg_revision/"}

	# Avoid checking out self-references.
	if [[ $pkg != $pkg_name ]]; then

		incoming=`git name-rev --name-only $b`
		rev_a=""
		rev_b=`get_trailer $b git-pkgs-revision`

		if git rev-parse -q --verify "$a^{commit}" > /dev/null; then
			existing=`git name-rev --name-only $a`
			rev_a=`get_trailer $a git-pkgs-revision`

			rev=$rev_a
			case $strategy in
				max)
					rev=`max_revision $rev_a $rev_b`
				;;
				min)
					rev=`min_revision $rev_a $rev_b`
				;;
				keep)
					rev=$rev_a
				;;
				update)
					rev=$rev_b
				;;
				interactive)
		 			echo "Package $pkg already installed:"
		 			echo " * [existing]        $existing ($rev_a)"
		 			echo " * [incoming]        $incoming ($rev_b)"
					echo "Replace existing with incoming? [y/N]"
					read_char < /dev/tty
		 			case $REPLY in
		 			[Yy])
						rev=$rev_b
						;;
					esac
				;;
			esac
		else
			rev=$rev_b
		fi
		add_package
	fi
}

# Add a new package.
cmd_add() {
	check_pkg_name

	read -r name revision url <<< "$@"
	if [ "$#" -eq 2 ]; then
		url=$(get_trailer "refs/pkgs/$pkg_name/HEAD/$name" git-pkgs-url)
	fi

	# N: adding "--depth=1" will add the orphan branch to .git/shallow,
	# even if the remote branch is already an orphan of depth 1.
	git fetch -f --no-tags $url	\
		"refs/pkgs/$name/$revision/*:refs/pkgs/$name/$revision/*"
		# "refs/releases/$revision/*:refs/pkgs/$name/$revision/*"

	ref="refs/pkgs/$name/$revision/$name"
	if ! ref_exists $ref || [[ $revision != $(get_trailer $ref "git-pkgs-revision") ]]; then
		# N: the target ref (i.e. the package itself), may already exist, if there is
		# a cyclic dependency. We assume that the specified revision will void this
		# dependency, since a cyclic dependency can only require an earlier revision.
		git fetch -f --depth=1 --no-tags $url "$revision:$ref" || die

		# Make shallow branch an orphan.
		orphanize
	fi

	echo "From $url"
	echo " * [new package]     $name@$revision"

	add_pkgs_dependencies

	if [[ $namespace ]]; then
		pkg_revision="$pkg_revision/$namespace"
	fi

	# select referenced packages into refs/pkgs/$pkg_name/$pkg_revision
	echo "Depencies resolved:"
	git fetch . "refs/pkgs/$name/$revision/*:refs/pkgs/$pkg_name/$pkg_revision/*" --no-tags --porcelain | \
		while read status a b target; do
			resolve_transitive_dependency $a $b $target
		done

	config_write
}

# Import a directory without mutating it (no git init inside).
cmd_add-dir() {
	check_pkg_name

	read -r name revision src <<< "$@"

	[ $name ] || die "fatal: No package name was given."
	[ $revision ] || die "fatal: No revision was given."
	[ $src ] || die "fatal: No source path was given."
	[ -d "$src" ] || die "fatal: Path does not exist or is not a directory: $src"

	src=$(realpath "$src")
	git_dir=$(git rev-parse --git-dir) || die "fatal: Could not resolve git dir."

	tmp_index=$(mktemp) || die "fatal: Could not create temporary index."
	# Remove the empty file so git can create a fresh index here.
	rm -f "$tmp_index"
	cleanup_index() { rm -f "$tmp_index"; }
	trap cleanup_index RETURN

	# Stage files from src into a throwaway index tied to our current repo.
	GIT_INDEX_FILE=$tmp_index git --git-dir="$git_dir" --work-tree="$src" add -A . || die "fatal: Failed to stage source directory."

	# Optionally inject a synthetic pkgs.json into the staged tree without touching src.
	if [[ -n ${PKGS_IMPORT_CONFIG_JSON:-} ]]; then
		blob=$(printf '%s' "$PKGS_IMPORT_CONFIG_JSON" | git hash-object -w --stdin) || die "fatal: Could not write pkgs.json blob."
		GIT_INDEX_FILE=$tmp_index git update-index --add --cacheinfo 100644 $blob "$GIT_PKGS_JSON" || die "fatal: Could not stage synthetic pkgs.json."
	fi

	tree=$(GIT_INDEX_FILE=$tmp_index git write-tree) || die "fatal: Could not write tree for $name."
	commit_msg=$(cat <<EOF
git-pkgs import $name@$revision

git-pkgs-name: $name
git-pkgs-type: $pkg_type
git-pkgs-revision: $revision
git-pkgs-url: $src
EOF
)
	commit=$(GIT_INDEX_FILE=$tmp_index git commit-tree "$tree" -m "$commit_msg")

	trap - RETURN
	cleanup_index

	# Publish the imported tree as a package ref.
	git update-ref "refs/pkgs/$name/$revision/$name" "$commit"

	# Attach it to the current package graph.
	if [[ $namespace ]]; then
		pkg_revision="$pkg_revision/$namespace"
	fi
	target="refs/pkgs/$pkg_name/$pkg_revision/$name"
	git update-ref "$target" "$commit"

	# Record dependency in pkgs.json (skip self if name == pkg_name).
	if [[ $name != $pkg_name ]]; then
		add_pkgs_dependencies
		config_write
	fi

	# Materialize worktree if applicable.
	pkg=$name
	worktree_reset $pkg
	worktree_checkout

	echo "Imported $name@$revision from $src"

	# Fetch and resolve transitive dependencies into current graph.
	echo "Dependencies resolved:"
	git fetch . "refs/pkgs/$name/$revision/*:refs/pkgs/$pkg_name/$pkg_revision/*" --no-tags --porcelain | \
		while read status a b target; do
			resolve_transitive_dependency $a $b $target
		done
}


# Create a new release (tag) of this package.
cmd_release() {
	revision=$1
	name=$pkg_name

	[ $revision ] || die "fatal: Revision/tag was not specified."

	check_pkg_name
	config_set_str "version" "$revision"
	config_write
	git add "$pkg_config_file"

	# Important: git trailers don't support empty messages!
	[ $message ] || message="Release $name@$revision."

	git -c trailer.ifexists=addIfDifferent commit -q --allow-empty --message="$message" \
		--trailer "git-pkgs-name:$name" \
		--trailer "git-pkgs-type:$pkg_type" \
		--trailer "git-pkgs-revision:$revision" \
		--trailer "git-pkgs-url:$url"

	git tag -f $revision

	# refs/pkgs/pkgs_app/HEAD/pkgs_app --> refs/pkgs/pkgs_app/1.0.0/pkgs_app
	git fetch -q . "refs/pkgs/$pkg_name/$pkg_revision/*:refs/pkgs/$name/$revision/*"

	# N: We can not use --depth=1 here. This will make the main branch grafted.
	# 1.0.0 --> refs/pkgs/pkgs_app/1.0.0/pkgs_app
	git fetch -q -f --no-tags . "$revision:refs/pkgs/$name/$revision/$name"

	git update-ref "refs/pkgs/$name/$pkg_revision/$name" "refs/pkgs/$name/$revision/$name"

	# Remove worktree.
	worktree_reset $name
}

# Checkout a specific release (including dependencies).
cmd_checkout() {
	check_pkg_name

	revision=$1

	# Refuse to check out non-existing revision.
	[[ $(git for-each-ref --count=1 "refs/pkgs/$pkg_name/$revision") ]] || die "No such git-pkgs release: $revision"

	echo "Checking out revision: $revision"

	git checkout -q $revision

	if [[ $revision != "HEAD" ]]; then
		git for-each-ref "refs/pkgs/$pkg_name/HEAD"	--format="%(refname)" |
			while read ref; do
				pkg=${ref#"refs/pkgs/$pkg_name/HEAD/"}
				worktree_reset $pkg
				git update-ref -d $ref
			done
	fi

	# Q: check out e.g. "refs/pkgs/$pkg_name/$revision/dev/*" ?
	git fetch -q -p -f . "refs/pkgs/$pkg_name/$revision/*:refs/pkgs/$pkg_name/HEAD/*"

	git for-each-ref "refs/pkgs/$pkg_name/HEAD"	--format="%(refname)" |
		while read target; do
			pkg=${target#"refs/pkgs/$pkg_name/HEAD/"}
			if [[ $pkg_name != $pkg ]]; then
				# Q: multiple prefixes?
				worktree_checkout
			fi
		done
}

# List all (remote) release tags of a package.
cmd_ls-releases() {
	pkg=$1
	[[ $pkg ]] || die "fatal: required argument <pkg> missing."
	url=$(get_trailer "refs/pkgs/$pkg_name/$pkg_revision/$pkg" git-pkgs-url)
	git ls-remote --refs --tags $url
}

# Get status (commit/revision) of all packages.
cmd_status() {
	fmt="%(objectname)    %(contents:trailers:key=git-pkgs-name,key=git-pkgs-revision,valueonly,separator=@)"
	git for-each-ref --format="$fmt" "refs/pkgs/$pkg_name/$pkg_revision"
}

# Push release and dependent packages to a remote.
cmd_push() {
	remote=$1
	[ $remote ] || die "fatal: No remote was provided. Where do you want to push?"
	revision=${2:-$(get_revision)}
	git push -f $remote HEAD $revision "refs/pkgs/*"
}

# Fetch release and its packages from a remote.
cmd_fetch() {
	origin=$1
	revision=$2
	if [ $all ]; then
		git fetch $origin $revision "refs/pkgs/*:refs/pkgs/*" "refs/tags/*:refs/tags/*"
	else
		if [ $revision ]; then
			git fetch $origin $revision "refs/pkgs/$pkg_name/$revision/*:refs/pkgs/$pkg_name/$revision/*"
		fi
	fi
}

# Pull release and check out its packages.
cmd_pull() {
	read -r remote revision <<< "$@"
	cmd_fetch $remote $revision || die
	cmd_checkout $revision
}

# Clone a release and check out its packages.
cmd_clone() {
	read -r url dst revision <<< "$@"
	git clone $url $dst || die

	revision=${revision:-HEAD}

	cd $dst \
		&& cmd_fetch origin $revision \
		&& pkg_name=$(get_trailer HEAD "git-pkgs-name") \
		&& git pkgs checkout $revision
}

# Launch stdio mcp server.
cmd_mcp() {
	git pkgs-mcp "$@"
}

# N: compatible with awk and gawk, but not *mawk*.
format_tree() {
	printf "\e[0;90m"
	awk '
    function tip(new) { stem = substr(stem, 1, length(stem) - 4) new }
    {
        path[NR] = $0
    }
    END {
        elbow = "└── "; pipe = "│   "; tee = "├── "; blank = "    "
        none = ""
        for (row = NR; row > 0; row--) {
            growth = gsub(/[^:]*:/, "", path[row]) - slashes
            if (growth == 0) {
                tip(tee)
            }
            else if (growth > 0) {
                if (stem) tip(pipe) # if...: stem is empty at first!
                for (d = 1; d < growth; d++) stem = stem blank
                stem = stem elbow
            }
            else {
                tip(none)
                below = substr(stem, length(stem) - 4, 4)
                if (below == blank) tip(elbow); else tip(tee)
            }
            path[row] = stem path[row]
            slashes += growth
        }
				print "."
        for (row = 1; row <= NR; row++) print path[row]
    }'
}

# Format a package line.
fmt_pkg() {
	pkg=$1
	revision=$2
	extra=$3

	if refs_equal "refs/pkgs/$pkg_name/$pkg_revision/$pkg" "refs/pkgs/$pkg/$revision/$pkg"; then
		echo -e "\e[0;39m$pkg \e[1;39m$revision\e[0;90m $extra\e[0;90m"
 	else
		echo -e "\e[0;90m$pkg $revision $extra"
 	fi
}

# Build dependency tree.
pkgs_tree() {
	local name=$1 rev=$2
 	declare -A seen prefixes
	declare -a deps tree

	tree+=("$name $rev")

	count=1
	while ((count > 0 )); do
		count=0
		for i in "${!tree[@]}"; do
			read name rev prefix <<< "${tree[$i]}"
			deps+=("$name $rev $prefix")
			id="${name}@${rev}"
			if [[ ${seen[$id]} ]]; then
				continue
			fi

			# Use package config from package itself, unless it's the root package.
			if ! [[ $name == $pkg_name && $rev == $pkg_revision ]]; then
				config=$(git cat-file -p "refs/pkgs/$name/$rev/$name:$GIT_PKGS_JSON" 2> /dev/null || echo '{}')
			fi

			while read dep_name dep_rev; do
				[[ -n $dep_name ]] || continue
				deps+=("$dep_name $dep_rev $prefix:$name@$rev")
			done <<< $(get_dependencies)

			seen[$id]=1
			prefixes[$id]=$prefix
			((count++))
		done
		tree=("${deps[@]}")
		deps=()
	done

	for i in "${!tree[@]}"; do
		read name rev prefix <<< "${tree[$i]}"
		id="${name}@${rev}"
		p=${prefixes[$id]}
		if [[ $p == $prefix ]]; then
			extra=""
		else
			extra="deduped"
		fi
		pkg=$(fmt_pkg "$name" "$rev" "$extra")
		echo "$prefix:$pkg"
	done
}

# Show dependency tree.
cmd_tree() {
	revision=${1:-"HEAD"}
	pkgs_tree $pkg_name $revision | format_tree
}

# Prune unreachable grafted commits.
cmd_prune() {
	git reflog expire --expire-unreachable=all --all
	git gc --prune=now
}

# Resolve removed into existing.
resolve_removed() {
	removed=$1
	pkg_rev=$2
	target="refs/pkgs/$pkg_name/HEAD/$removed"
	get_root_packages $pkg_name HEAD |
		while read sha; do
			root=`get_trailer $sha git-pkgs-name`

			if [[ $root != $pkg_name ]]; then
				revision=`get_trailer $sha git-pkgs-revision`
				git for-each-ref "refs/pkgs/$root/$revision/$removed" |
					while read new type ref; do
						old=`git rev-parse $target 2> /dev/null`
						resolve_transitive_dependency $old $new $target
					done
			fi
		done
}

remove_packages() {
	name=$1
	revision=$2
	git for-each-ref "refs/pkgs/$name/$revision" |
		while read commit type ref; do
			pkg=${ref#"refs/pkgs/$name/$revision/"}
			pkg_rev=`get_trailer $commit git-pkgs-revision`
			# Only remove if part of HEAD.
			if git name-rev --no-undefined --refs="refs/pkgs/$pkg_name/$pkg_revision/$pkg" $ref &> /dev/null; then
				worktree_reset $pkg
				# Delete package from HEAD.
				git update-ref -d "refs/pkgs/$pkg_name/$pkg_revision/$pkg" &> /dev/null
				echo "$pkg $pkg_rev"
			fi
		done
}

# Remove a package.
cmd_remove() {
  name=$1
	[ $name ] || die "fatal: No package name was given. What should be removed?"
	# Only remove non-transitive packages.
	if is_non_transitive $name; then
		sha=`git rev-parse "refs/pkgs/$pkg_name/$pkg_revision/$name"` || die "fatal: Could not extract commit."
		revision=`get_trailer $sha "git-pkgs-revision"`
		echo "Removing $name@$revision"
		echo "Depencies resolved:"
		# Process transitory dependencies
		items=$(remove_packages $name $revision)
		echo "$items" |
			while read removed pkg_rev; do
				echo " * [remove]          $removed@$pkg_rev"
			done
		echo "$items" |
			while read removed pkg_rev; do
				resolve_removed $removed $pkg_rev
			done
	else
		die "fatal: Package is not a direct dependency."
	fi
}

# Import from json (requires jq).
cmd_json-import() {
	filename=${1:-/dev/stdin}
	jq -r '.packages[] | "\(.name) \(.revision) \(.url)"' $filename |
		while read name revision url; do
			git pkgs add $name $revision $url
		done
}

# Export to json-format.
cmd_json-export() {
	check_pkg_name

	printf_json() {
		output=`printf $@`; echo ${output/%,}
	}

	list_packages() {
		git for-each-ref "refs/pkgs/$pkg_name/$revision" \
			--format="%(authorname)|%(authoremail)|%(contents:subject)|%(objectname)|$(trailers git-pkgs-name git-pkgs-revision git-pkgs-commit git-pkgs-url)" |
			while IFS="|" read author email subject objname name revision commit url; do
				if is_non_transitive $name || [ $all ]; then
					IFS="|"
					printf_json '"%s":"%s",' "name|$name|revision|$revision|author|$author|email|$email|description|$subject|snapshot|$objname|reference|$commit|url|$url|mirror|$pkg_url|"
				fi
			done
	}

	revision=${1:-HEAD}

	IFS=$'\n' && packages=$(printf_json "{%s}," $(list_packages))
	echo "{\"name\":\"$pkg_name\",\"revision\":\"$(get_revision)\",\"packages\":[$packages]}"
}

# Get all revisions of a package.
get_revisions() {
	pkg=$1
	git ls-remote . "refs/pkgs/$pkg/*/$pkg" |
		while read commit ref; do
			rev=${ref#"refs/pkgs/$pkg/"}
			rev=${rev%"/$pkg"}
			if [[ $rev == $revision || $rev == 'HEAD' ]]; then
				echo -e "\e[1;37m$rev\e[0;37m"
			else
				echo $rev
			fi
		done
}

# Show package information.
cmd_show() {
	pkg=$1
	[[ $pkg ]] || die "fatal: no package name provided."

	data=$(git for-each-ref "refs/pkgs/$pkg_name/HEAD/$pkg" --format="%(authorname)|%(authoremail)|%(authordate:short)|%(contents:subject)|%(objectname)|$(trailers git-pkgs-name git-pkgs-type git-pkgs-revision git-pkgs-commit git-pkgs-url)")
	[[ $data ]] || die "fatal: package '$pkg' not found."

	IFS="|" read author email authordate subject objname name type revision commit url <<< $data

	revs=$(printf "%s, " $(get_revisions $pkg | sort -V -r))
	revs=${revs/%, }

	echo -e "\e[0;36mname       : \e[0;37m$pkg"
	echo -e "\e[0;36mversions   : \e[0;37m$revs"
	echo -e "\e[0;36mdecription : \e[0;37m$subject"
	echo -e "\e[0;36mtype       : \e[0;37m$type"
	echo -e "\e[0;36mauthor     : \e[0;37m$author $email"
	echo -e "\e[0;36mdate       : \e[0;37m$authordate"
	echo -e "\e[0;36mpath       : \e[0;37m$prefix/$pkg"
	echo -e "\e[0;36msnapshot   : \e[0;37m$objname"
	echo -e "\e[0;36mreference  : \e[0;37m$commit"
	echo -e "\e[0;36mrepository : \e[0;37m$url"
	echo ""
	echo -e "\e[0;36mdependencies (direct & indirect):"
  git for-each-ref "refs/pkgs/$pkg/$revision/" --format="$(trailers git-pkgs-name git-pkgs-revision)" |
		while IFS="|" read name rev; do
			[[ $name != $pkg ]] && echo -e "\e[0;37m- $name \e[1;39m$rev\e[0m"
		done

}

cmd_config_list() {
	echo "$config"
}

cmd_config_get() {
	config_get "$1"
}

cmd_config_add() {
	key=$1;	value=$2
	case $value in
	  "true"|"false") ;;
		*) value="\"$value\""
	esac
	config_set "$key" "$value"
	config_write
}

cmd_config() {
	command=$1
	shift
	"cmd_config_$command" "$@"
}

# All commands but "clone" and "mcp" require a work tree.
[[ $command != "clone" && $command != "mcp" ]] && require_git_version && . git-sh-setup && require_work_tree

"cmd_$command" "$@"
