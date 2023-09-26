#!/usr/bin/bash
#
# git-pkgs.sh: the decentralized package manager for git.
#
# Copyright (c) 2023 Mattias Andersson <mattias@longknot.com>.

if [ $# -eq 0 ]; then
  set -- -h
fi

OPTS_SPEC="\
git pkgs release [-m <message>] [--skip-self] <revision>
git pkgs add [-s <strategy>] [-P <prefix>] <pkg> <revision> [<remote>]
git pkgs remove [-P <prefix>] <pkg>
git pkgs checkout [-P <prefix>] <revision>
git pkgs fetch [--all] <remote> [<revision>]
git pkgs push <remote> [<revision>]
git pkgs pull <remote> [<revision>]
git pkgs clone <remote> [<directory> [<revision>]]
git pkgs ls-releases <pkg>
git pkgs status [<revision>]
git pkgs tree [<revision>]
git pkgs json-import [<filename>]
git pkgs json-export [--all] [<revision>]
--
h,help        show the help
q             quiet
P,prefix=     prefix
m,message=    commit message
s,strategy=   conflict resolution strategy ('max', 'min', 'keep', 'update', 'interactive')
all           include all dependencies in an export (both direct and transitive).
skip-self     do not include package itself in a release
pkg-name=     package name (optional)
"

eval "$(echo "$OPTS_SPEC" | git rev-parse --parseopt -- "$@" || echo exit $?)"

pkg_name=$(git config --get pkgs.name)
prefix=$(git config --get pkgs.prefix)
message=
strategy=$(git config --default "max" --get pkgs.strategy)
all=
skip_self=

while [ $# -gt 0 ]; do
	opt="$1"
	shift
	case "$opt" in
		-q) quiet=1 ;;
		-P) prefix="$1"; shift;;
		-m) message="$1"; shift;;
		-s) strategy="$1"; shift;;
		--all) all=1 ;;
		--skip-self) skip_self=1 ;;
		--pkg-name) pkg_name="$1"; shift;;
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
	git describe --tags
}

pkg_path() {
	path=$1
	[ ! -z $prefix ] && path=$prefix/$path
	echo $path
}

worktree_reset() {
	# remove worktree if it already exists.
	path=$(pkg_path $1)
	if [ -d "$path" ]
	then
    git worktree remove -f "$path"
		git worktree prune
	fi
}

# If pkg exists, use "git checkout", otherwise "git worktree add".
worktree_checkout() {
	path=$(pkg_path $pkg)
	if [ -d $path ];
	then
		git -C $path checkout -q "refs/releases/HEAD/$pkg"
	else
		git worktree add -q -f $path "refs/releases/HEAD/$pkg"
	fi
}

# Hackish, but it works.
is_non_transitive() {
	git name-rev --no-undefined --refs="refs/pkgs/$1/*/$1" "refs/releases/HEAD/$1" &> /dev/null
}

# Extract trailers for 'git for-each-ref'.
trailers() {
	printf "%%(contents:trailers:"
	for key in $@; do
		printf "key=$key,"
	done
	printf "valueonly,separator=|)"
}

# Make branch an orphan.
orphanize() {
	src="refs/pkgs/$name/$revision/$name"
	commit=`git rev-parse $src`
	worktree_reset $name

	path=$(pkg_path $name)
	#git worktree add -q --no-checkout $name $src
	git worktree add -q --no-checkout $path $src

	git -C "$path" checkout -q -f --orphan "$name"
	git -C "$path" commit -C $src -q \
	  --trailer "git-pkgs-prefix:$prefix" \
		--trailer "git-pkgs-name:$name" \
		--trailer "git-pkgs-revision:$revision" \
		--trailer "git-pkgs-commit:$commit" \
		--trailer "git-pkgs-url:$url"

	git update-ref -d $src
	git fetch -q . "refs/heads/$name:$src" --no-tags --force
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
  	git fetch -q . "$incoming:$target" --no-tags --force
		worktree_reset $pkg
		path=$(pkg_path $pkg)
		git worktree add -q -f $path $target
	fi
}

resolve_transitive_dependency() {
	a=$1
	b=$2
	target=$3

	pkg=${target#"refs/releases/HEAD/"}
	echo $pkg
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

cmd_add() {
	read -r name revision url <<< "$@"
	if [ "$#" -eq 2 ]; then
		url=$(get_trailer "refs/releases/HEAD/$name" git-pkgs-url)
	fi

	# N: adding "--depth=1" will add the orphan branch to .git/shallow,
	# even if the remote branch is already an orphan of depth 1.
  git fetch -f --no-tags $url	\
		"refs/releases/$revision/*:refs/pkgs/$name/$revision/*"

	# Is there already an orphanized version of the package in the release?
	# !!!! --> cyclic dependency e@1.1 in e@1.2-release?

	ref="refs/pkgs/$name/$revision/$name"
	if ! ref_exists $ref || [[ $revision != $(get_trailer $ref "git-pkgs-revision") ]]; then
		# N: the target ref (i.e. the package itself), may already exist, if there is
		# a cyclic dependency. We assume that the specified revision will void this
		# dependency, since a cyclic dependency can only require an earlier revision.
		git fetch -f --depth=1 --no-tags $url \
			"$revision:refs/pkgs/$name/$revision/$name" || die

		# Make shallow branch an orphan.
		orphanize
	fi

	echo "From $url"
	echo " * [new package]     $name@$revision"

	# select referenced packages into refs/release/head
	echo "Depencies resolved:"
	git fetch . "refs/pkgs/$name/$revision/*:refs/releases/HEAD/*" --no-tags --porcelain | \
		while read status a b target; do
			echo $target
			resolve_transitive_dependency $a $b $target
		done
}

# Create a new release (tag) of this package.
cmd_release() {
	revision=$1
	[ $revision ] || die "fatal: Revision/tag was not specified."

	if [[ ! $pkg_name && ! $skip_self ]]; then
		echo 'fatal: package does not have a name.'
		echo 'Configure a package name like this:'
		echo "'git config pkgs.name <name>'"
		die
	fi

	git add .
	git commit -q --message="$message"
	git tag $revision
	git fetch -q . "refs/releases/HEAD/*:refs/releases/$revision/*"

	if [[ $pkg_name && ! $skip_self  ]]; then
		name=$pkg_name
		# N: We can not use --depth=1 here. This will make the main branch grafted.
		git fetch -q -f --no-tags . \
			"$revision:refs/pkgs/$name/$revision/$name"
		orphanize
		git fetch -q -f . "refs/pkgs/$name/$revision/$name:refs/releases/$revision/$name"
		# Remove worktree.
		worktree_reset $name
	else
		echo "warning: package itself was not included as an orphaned ref in the release."
	fi
}

# Checkout a specific release (including dependencies).
cmd_checkout() {
	revision=$1
	echo "Checkout revision $revision."
	git checkout -q $revision

	if [[ $revision != "HEAD" ]]; then
		git for-each-ref "refs/releases/HEAD"	--format="%(refname)" |
			while read ref; do
				pkg=${ref#"refs/releases/HEAD/"}
				worktree_reset $pkg
				git update-ref -d $ref
			done
	fi

	git fetch -q -p -f . "refs/releases/$revision/*:refs/releases/HEAD/*"

	git for-each-ref "refs/releases/HEAD"	--format="%(refname)" |
		while read ref; do
			pkg=${ref#"refs/releases/HEAD/"}
			worktree_checkout $pkg
		done
}

# List all (remote) release tags of a package.
cmd_ls-releases() {
	url=$(get_trailer "refs/releases/HEAD/$1" git-pkgs-url)
	git ls-remote --refs --tags $url
}

# Get status (commit/revision) of all packages.
cmd_status() {
	fmt="%(objectname)    %(contents:trailers:key=git-pkgs-name,key=git-pkgs-revision,valueonly,separator=@)"
	git for-each-ref --format="$fmt" 'refs/releases/HEAD'
}

# Push release and dependent packages to a remote.
cmd_push() {
	remote=$1
	[ $remote ] || die "fatal: No remote was provided. Where do you want to push?"
	revision=${2:-$(get_revision)}
	git push -f $remote HEAD $revision "refs/releases/$revision/*" "refs/pkgs/*" "refs/releases/HEAD/*"
}

cmd_fetch() {
	origin=$1
	revision=$2
	if [ $all ]; then
		git fetch $origin $revision "refs/releases/*:refs/releases/*" "refs/pkgs/*:refs/pkgs/*" "refs/tags/*:refs/tags/*"
	else
		if [ $revision ]; then
			git fetch $origin $revision "refs/releases/$revision/*:refs/releases/$revision/*"
		fi
	fi
}

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
		&& cmd_checkout $revision
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

		git for-each-ref "refs/pkgs/$pkg/$revision" |
  		while read commit type ref; do
  			package_tree "$1:$pkg@$revision" $release
  		done
  fi
}

# List packages that were added by "git pkgs add".
get_root_packages() {
	revision=$1
	git for-each-ref "refs/releases/$revision" |
		while read commit type ref; do
			pkg=${ref#"refs/releases/$revision/"}
			if is_non_transitive $pkg || [ $all ]; then
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
	release=${1:-HEAD}
	release_tree $release | format_tree
}

# Prune unreachable grafted commits.
cmd_prune() {
	git reflog expire --expire-unreachable=all --all
	git gc --prune=now
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
			git for-each-ref "refs/pkgs/$root/$revision/$removed" |
				while read new type ref; do
					old=`git rev-parse $target 2> /dev/null`
					resolve_transitive_dependency $old $new $target
				done
		done
}

# Remove a package.
cmd_remove() {
  name=$1
	[ $name ] || die "fatal: No package name was given. What should be removed?"
	# Only remove non-transitive packages.
	if is_non_transitive $name; then
		sha=`git rev-parse "refs/releases/HEAD/$name"` || die
		revision=`get_trailer $sha "git-pkgs-revision"`
		echo "Removing $name@$revision"
		echo "Depencies resolved:"
		# Process transitory dependencies
		git for-each-ref "refs/pkgs/$name/$revision" |
			while read commit type ref; do
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

# Import from json (requires jq).
cmd_json-import() {
	filename=$1
	[ $filename ] || die "fatal: No filename was given. What should be imported?"
	jq -r '.packages[] | "\(.name) \(.revision) \(.url)"' $filename |
		while read name revision url; do
			git pkgs add $name $url $revision
		done
}

# Export to json-format.
cmd_json-export() {

	printf_json() {
		output=`printf $@`; echo ${output/%,}
	}

	list_packages() {
		git for-each-ref "refs/releases/$revision" \
			--format="%(authorname)|%(authoremail)|%(contents:subject)|$(trailers git-pkgs-name git-pkgs-revision git-pkgs-commit git-pkgs-url)" |
			while IFS="|" read author email subject name revision commit url; do
				if is_non_transitive $name || [ $all ]; then
					IFS="|"
					printf_json '"%s":"%s",' "name|$name|revision|$revision|commit|$commit|url|$url|author|$author|email|$email|description|$subject"
				fi
			done
	}

	revision=${1:-HEAD}

	IFS=$'\n' && packages=$(printf_json "{%s}," $(list_packages))
	echo "{\"name\":\"$pkg_name\",\"revision\":\"$(get_revision)\",\"packages\":[$packages]}"
}

# All commands but "clone" require a work tree.
[[ $command != "clone" ]] && . git-sh-setup && require_work_tree

"cmd_$command" "$@"
