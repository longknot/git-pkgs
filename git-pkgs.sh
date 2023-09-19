#!/usr/bin/bash
#
# git-pkgs.sh: the decentralized package manager for git.
#
# Copyright (c) 2023 Mattias Andersson <mattias@longknot.com>.

if [ $# -eq 0 ]; then
  set -- -h
fi

OPTS_SPEC="\
git pkgs release [-m <message>] <revision>
git pkgs add [-s <strategy>] <pkg> <remote> <revision>
git pkgs remove <pkg>
git pkgs checkout <revision>
git pkgs push <remote> <revision>
git pkgs clone <remote>
git pkgs ls-releases <pkg>
git pkgs status [revision]
git pkgs tree [revision]
--
h,help        show the help
q             quiet
m,message=    commit message
s,strategy=   conflict resolution strategy ('max', 'keep', 'update', 'interactive')
"

eval "$(echo "$OPTS_SPEC" | git rev-parse --parseopt -- "$@" || echo exit $?)"

strategy=max
message=

while [ $# -gt 0 ]; do
	opt="$1"
	shift
	case "$opt" in
		-q) quiet=1 ;;
		-m) message="$1"; shift;;
		-s) strategy="$1"; shift;;
		--) break ;;
		*) die "Unexpected option: $opt" ;;
	esac
done

command="$1"
shift

# Read char function that works with both bash and zsh.
read_char() {
  stty -icanon -echo
  REPLY=$(dd bs=1 count=1 2>/dev/null)
  stty icanon echo
}

get_trailer() {
	git -P show -s --pretty="%(trailers:key=$2,valueonly)%-" $1
}

worktree_reset() {
	# remove worktree if it already exists.
	if [ -d "$1" ]
	then
    git worktree remove -f "$1"
		git worktree prune
	fi
}

# If pkg exists, use "git checkout", otherwise "git worktree add".
worktree_checkout() {
	if [ -d $pkg ];
	then
		git -C $pkg checkout -q $ref
	else
		git worktree add -q -f $pkg $ref
	fi
}

# Hackish, but it works.
is_non_transitive() {
	git name-rev --no-undefined --refs="refs/pkgs/$1/*/$1" "refs/releases/HEAD/$1" &> /dev/null
}

# Make branch an orphan.
orphanize() {
	commit=`git rev-parse refs/releases/HEAD/$name`
	worktree_reset $name

	# remove existing branch.
	git branch -q -D $name 2> /dev/null

	git worktree add -q $name "refs/releases/HEAD/$name"
	git -C "$name" checkout -q -f --orphan "$name"
	git -C "$name" commit -C $commit -q \
		--trailer "git-pkgs-name:$name" \
		--trailer "git-pkgs-commit:$commit" \
		--trailer "git-pkgs-revision:$revision" \
		--trailer "git-pkgs-url:$url"

	# update refs/releases/head/[package] to point to the new orphanized branch.
	git fetch -q . "refs/heads/$name:refs/releases/HEAD/$name" --no-tags --force
	git fetch -q . "refs/heads/$name:refs/pkgs/$name/$revision/$name" --no-tags --force
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
  	git fetch -q . "$incoming:$target" --no-tags --force
		worktree_reset $pkg
		git worktree add -q -f $pkg $target
	fi
}

resolve_transitive_dependency() {
	pkg=${target#"refs/releases/HEAD/"}

	incoming=`git name-rev --name-only $b`
	rev_b=`get_trailer $b git-pkgs-revision`

	if git rev-parse -q --verify "$a^{commit}" > /dev/null; then
		existing=`git name-rev --name-only $a`
		rev_a=`get_trailer $a git-pkgs-revision`

		rev=$rev_a
		case $strategy in
			max)
				max=`printf "$rev_a\n$rev_b" | sort -V | tail -1`
				if [[ $max == $rev_b ]]
				then
					rev=$rev_b
				fi
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
}

cmd_add() {
	if [ "$#" -eq 3 ]; then
  	read -r name url revision <<< "$@"
	elif [ "$#" -eq 2 ]; then
		read -r name revision <<< "$@"
		url=`git -C $name -P log -n 1 --pretty='%(trailers:key=git-pkgs-url,valueonly)%-'`
	fi

	# N: this will be rejected (non-fast forward) unless using --force.
	git fetch -f --depth=1 --no-tags $url \
		"$revision:refs/releases/HEAD/$name" || die

	# N: adding "--depth=1" will add the orphan branch to .git/shallow,
	# even if the remote branch is already an orphan of depth 1.
  git fetch -f --no-tags $url	\
		"refs/releases/$revision/*:refs/pkgs/$name/$revision/*"

	# make shallow branch an orphan.
	orphanize

	echo "From $url"
	echo " * [new package]     $name@$revision"

	# select referenced packages into refs/release/head
	echo "Depencies resolved:"
	git fetch . "refs/pkgs/$name/$revision/*:refs/releases/HEAD/*" --no-tags --porcelain | \
		while read status a b target; do
			resolve_transitive_dependency
	  done
}

# Create a new release (tag) of this package.
cmd_release() {
	revision=$1
	git add .
	git commit -q --message="$message" \
		--trailer "git-pkgs-release:$revision"
	git tag $revision
	git fetch -q . "refs/releases/HEAD/*:refs/releases/$revision/*"
}

# Checkout a specific release (including dependencies).
cmd_checkout() {
	revision=$1
	echo "Checkout revision $revision."
	git checkout -q $revision
	# N: rejected non-fast-forward.
	git ls-remote . "refs/releases/HEAD/*" |
		while read commit ref; do
			pkg=${ref#"refs/releases/HEAD/"}
			worktree_reset $pkg
		done

	git fetch -q -p -f . "refs/releases/$revision/*:refs/releases/HEAD/*"
	git ls-remote . "refs/releases/HEAD/*" |
		while read commit ref; do
			pkg=${ref#"refs/releases/HEAD/"}
			worktree_checkout
		done
}

# List all (remote) release tags of a package.
cmd_ls-releases() {
	package=$1
	url=`git -C $package -P log -n 1 --pretty='%(trailers:key=git-pkgs-url,valueonly)%-'`
	git ls-remote --refs --tags $url
}

# Get status (commit/revision) of all packages.
cmd_status() {
	git ls-remote . 'refs/releases/HEAD/*' |
		while read commit pkg; do
			git -P log -n 1 $commit --pretty="$commit     %(trailers:key=git-pkgs-name,valueonly)%-@%(trailers:key=git-pkgs-revision,valueonly)%-"
		done
}

# Push release and dependent packages to a remote.
cmd_push() {
	read -r remote revision <<< "$@"
	git push -f $remote HEAD $revision "refs/releases/$revision/*" "refs/pkgs/*" "refs/releases/HEAD/*"
}

# Clone a release and check out its packages.
cmd_clone() {
	read -r url dst <<< "$@"
	git clone $url $dst

	git -C $dst config --add remote.origin.fetch "+refs/releases/*:refs/releases/*"
	git -C $dst config --add remote.origin.fetch "+refs/pkgs/*:refs/pkgs/*"
	git -C $dst config --add remote.origin.fetch "+refs/tags/*:refs/tags/*"

	git -C $dst fetch origin
	git -C $dst pkgs checkout HEAD
}

format_tree() {
	awk '
    function tip(new) { stem = substr(stem, 1, length(stem) - 4) new }
    {
        path[NR] = $0
    }
    END {
        elbow = "└── "; pipe = "│   "; tee = "├── "; blank = "    "
        none = ""
        #
        # Model each stem on the previous one, going bottom up.
        for (row = NR; row > 0; row--) {
            #
            # gsub: count (and clean) all slash-ending components; hence,
            # reduce path to its last component.
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
        root = "."; print root
        for (row = 1; row <= NR; row++) print path[row]
    }'
}

package_tree() {
	local pkg=`get_trailer $commit git-pkgs-name`
	local release=$2

	# Avoid recursion.
	if [[ ! $1 =~ ":$pkg" ]]; then

  	revision=`get_trailer $commit git-pkgs-revision`
  	head_commit=`git rev-parse "refs/releases/$release/$pkg" 2> /dev/null`

  	if [[ $head_commit == $commit ]]; then
  		echo -e "$1:\e[1;32m$pkg \e[1;36m$revision\e[0m ✓"
  	else
  		echo -e "$1:\e[32m$pkg \e[36m$revision\e[0m"
  	fi

  	git ls-remote . "refs/pkgs/$pkg/$revision/*" |
  		while read commit ref; do
  			package_tree "$1:$pkg@$revision" $release
  		done
  fi
}

# List packages that were added by "git pkgs add".
get_root_packages() {
	revision=$1
	git ls-remote . "refs/releases/$revision/pkgs/*" |
		while read commit ref; do
			pkg=${ref#"refs/releases/$revision/"}
			if is_non_transitive $pkg; then
				echo $commit
			fi
		done
}

release_tree() {
	release=$1
	get_root_packages $release |
		while read commit; do
			package_tree "" $release
		done
}

cmd_tree() {
	release="$1"
	if [ -z $release ]; then
		release=HEAD
	fi
	release_tree $release  | format_tree
}

# Prune unreachable grafted commits.
cmd_prune() {
	git reflog expire --expire-unreachable=all --all
	git gc --prune=now
}

pkg_add_transitive() {
	git ls-remote . "refs/pkgs/$parent_pkg/$parent_rev/$pkg" |
		while read commit ref; do
			echo $ref
		done
}

# Resolve removed into existing.
resolve_removed() {
	removed=$1
	echo " * [remove]          $removed@$pkg_rev"
	target="refs/releases/HEAD/$removed"
	get_root_packages HEAD |
		while read sha; do
			root=`get_trailer $sha git-pkgs-name`
			revision=`get_trailer $sha git-pkgs-revision`
			git ls-remote . "refs/pkgs/$root/$revision/$removed" |
				while read commit ref; do
					a=`git rev-parse $target 2> /dev/null`
					b=$commit
					resolve_transitive_dependency
				done
		done
}

# Remove a package.
cmd_remove() {
  name=$1
	# Only remove non-transitive packages?
	if is_non_transitive $name; then
		sha=`git rev-parse "refs/releases/HEAD/$name"` || die
		revision=`get_trailer $sha "git-pkgs-revision"`
		echo "Removing $name@$revision"
		echo "Depencies resolved:"
		# Process transitory dependencies
		git ls-remote . "refs/pkgs/$name/$revision/*" |
			while read commit ref; do
				pkg=${ref#"refs/pkgs/$name/$revision/"}
				pkg_rev=`get_trailer $commit git-pkgs-revision`

				# Only remove if part of HEAD.
				if git name-rev --no-undefined --refs="refs/releases/HEAD/$pkg" $ref &> /dev/null; then
					worktree_reset $pkg
					# Delete package from HEAD.
					git update-ref -d "refs/releases/HEAD/$pkg" &> /dev/null
					resolve_removed $pkg
				fi
			done
	fi
}

# All commands but "clone" requires a work tree.
if [[ $command != "clone" ]]; then
	. git-sh-setup
	require_work_tree
fi

"cmd_$command" "$@"
