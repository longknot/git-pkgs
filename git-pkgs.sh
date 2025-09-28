#!/bin/bash
#
# git-pkgs.sh: the decentralized package manager for git.
#
# Copyright (c) 2023 Mattias Andersson <mattias@longknot.com>.

if [ $# -eq 0 ]; then
  set -- -h
fi

MIN_GIT_VERSION="2.41"
PKGS_DEFAULT_TYPE=${PKGS_DEFAULT_TYPE:-"pkg"}
PKGS_DEFAULT_STRATEGY=${PKGS_DEFAULT_STRATEGY:-"max"}

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
git pkgs tree [-d <depth>] [--all] [<revision>]
git pkgs show <pkg>
git pkgs json-import [<filename>]
git pkgs json-export [--all] [<revision>]
git pkgs mcp
--
h,help        show the help
q             quiet
P,prefix=     prefix
m,message=    commit message
s,strategy=   conflict resolution strategy ('max', 'min', 'keep', 'update', 'interactive')
all           include all dependencies in an export (both direct and transitive).
pkg-name=     package name (optional)
pkg-type=     package type (optional)
pkg-url=      package url (optional)
d,depth=      recursion depth
"

MCP_COMMAND_METADATA='
{
  "globals": [
    {"flag": "-q", "long": null, "property": "quiet", "description": "Suppress non-error output."},
    {"flag": "-P", "long": "--prefix", "takesValue": true, "valueName": "prefix", "description": "Override the working tree directory prefix."},
    {"flag": "-m", "long": "--message", "takesValue": true, "valueName": "message", "description": "Commit message used by release."},
    {"flag": "-s", "long": "--strategy", "takesValue": true, "valueName": "strategy", "description": "Conflict resolution strategy for add (max|min|keep|update|interactive)."},
    {"flag": null, "long": "--all", "description": "Include transitive dependencies."},
    {"flag": null, "long": "--pkg-name", "takesValue": true, "valueName": "name", "description": "Override configured package name."},
    {"flag": null, "long": "--pkg-url", "takesValue": true, "valueName": "url", "description": "Override configured package URL."},
    {"flag": null, "long": "--pkg-type", "takesValue": true, "valueName": "type", "description": "Override configured package type."},
    {"flag": "-d", "long": "--depth", "takesValue": true, "valueName": "depth", "description": "Limit recursion depth for tree."},
    {"flag": null, "long": null, "property": "repo_path", "takesValue": true, "valueName": "path", "description": "Repository root path (defaults to current directory)."}
  ],
  "commands": [
    {
      "name": "release",
      "description": "Record the current dependency set as a release tag.",
      "usage": "git pkgs release [-m <message>] <revision>",
      "options": [
        {"flag": "-m", "long": "--message", "takesValue": true, "valueName": "message", "description": "Commit message describing the release."}
      ],
      "positionals": [
        {"name": "revision", "required": true, "description": "Tag or ref that identifies the release."}
      ]
    },
    {
      "name": "add",
      "description": "Add or update a dependency for this package.",
      "usage": "git pkgs add [-s <strategy>] [-P <prefix>] <pkg> <revision> [<remote>]",
      "options": [
        {"flag": "-s", "long": "--strategy", "takesValue": true, "valueName": "strategy", "description": "Conflict resolution strategy when dependency already exists."},
        {"flag": "-P", "long": "--prefix", "takesValue": true, "valueName": "prefix", "description": "Override the working tree directory prefix."}
      ],
      "positionals": [
        {"name": "pkg", "required": true, "description": "Name of the dependency package."},
        {"name": "revision", "required": true, "description": "Revision to track from the dependency."},
        {"name": "remote", "required": false, "description": "Remote URL hosting the dependency."}
      ]
    },
    {
      "name": "remove",
      "description": "Remove a dependency and resolve transitive packages.",
      "usage": "git pkgs remove [-P <prefix>] <pkg>",
      "options": [
        {"flag": "-P", "long": "--prefix", "takesValue": true, "valueName": "prefix", "description": "Override the working tree directory prefix."}
      ],
      "positionals": [
        {"name": "pkg", "required": true, "description": "Name of the dependency to remove."}
      ]
    },
    {
      "name": "checkout",
      "description": "Checkout a recorded release and its dependencies.",
      "usage": "git pkgs checkout [-P <prefix>] <revision>",
      "options": [
        {"flag": "-P", "long": "--prefix", "takesValue": true, "valueName": "prefix", "description": "Override the working tree directory prefix."}
      ],
      "positionals": [
        {"name": "revision", "required": true, "description": "Release revision to restore."}
      ]
    },
    {
      "name": "fetch",
      "description": "Fetch git-pkgs metadata from a remote.",
      "usage": "git pkgs fetch [--all] <remote> [<revision>]",
      "options": [
        {"flag": null, "long": "--all", "description": "Fetch all releases and tags."}
      ],
      "positionals": [
        {"name": "remote", "required": true, "description": "Remote to fetch from."},
        {"name": "revision", "required": false, "description": "Specific release to fetch."}
      ]
    },
    {
      "name": "push",
      "description": "Push git-pkgs metadata to a remote.",
      "usage": "git pkgs push <remote> [<revision>]",
      "positionals": [
        {"name": "remote", "required": true, "description": "Remote to push to."},
        {"name": "revision", "required": false, "description": "Release revision to push."}
      ]
    },
    {
      "name": "pull",
      "description": "Fetch git-pkgs metadata and checkout a release.",
      "usage": "git pkgs pull <remote> [<revision>]",
      "positionals": [
        {"name": "remote", "required": true, "description": "Remote to pull from."},
        {"name": "revision", "required": false, "description": "Release revision to restore after fetch."}
      ]
    },
    {
      "name": "clone",
      "description": "Clone a repository and checkout dependencies for a release.",
      "usage": "git pkgs clone <remote> [<directory> [<revision>]]",
      "positionals": [
        {"name": "remote", "required": true, "description": "Remote repository to clone."},
        {"name": "directory", "required": false, "description": "Destination directory."},
        {"name": "revision", "required": false, "description": "Release revision to restore after clone."}
      ]
    },
    {
      "name": "ls-releases",
      "description": "List available release tags for a dependency.",
      "usage": "git pkgs ls-releases <pkg>",
      "positionals": [
        {"name": "pkg", "required": true, "description": "Dependency package name."}
      ]
    },
    {
      "name": "status",
      "description": "Show dependency revisions recorded in HEAD.",
      "usage": "git pkgs status",
      "positionals": []
    },
    {
      "name": "tree",
      "description": "Display the dependency tree for a release.",
      "usage": "git pkgs tree [-d <depth>] [--all] [<revision>]",
      "options": [
        {"flag": "-d", "long": "--depth", "takesValue": true, "valueName": "depth", "description": "Limit traversal depth."},
        {"flag": null, "long": "--all", "description": "Include transitive dependencies."}
      ],
      "positionals": [
        {"name": "revision", "required": false, "description": "Release revision to inspect."}
      ]
    },
    {
      "name": "show",
      "description": "Display metadata for a dependency recorded in HEAD.",
      "usage": "git pkgs show <pkg>",
      "positionals": [
        {"name": "pkg", "required": true, "description": "Dependency package name."}
      ]
    },
    {
      "name": "json-import",
      "description": "Import dependencies from a JSON manifest.",
      "usage": "git pkgs json-import [<filename>]",
      "positionals": [
        {"name": "filename", "required": false, "description": "File containing the JSON manifest (defaults to stdin)."}
      ]
    },
    {
      "name": "json-export",
      "description": "Export dependencies to a JSON manifest.",
      "usage": "git pkgs json-export [--all] [<revision>]",
      "options": [
        {"flag": null, "long": "--all", "description": "Include transitive dependencies."}
      ],
      "positionals": [
        {"name": "revision", "required": false, "description": "Release revision to export."}
      ]
    },
    {
      "name": "prune",
      "description": "Prune git objects created by git-pkgs orphan branches.",
      "usage": "git pkgs prune",
      "positionals": []
    }
  ]
}
'

eval "$(echo "$OPTS_SPEC" | git rev-parse --parseopt -- "$@" || echo exit $?)"

pkg_name=$(git config --get pkgs.name)
pkg_url=$(git config --get pkgs.url)
pkg_url=${pkg_url:-$(git config --get remote.origin.url)}
pkg_type=$(git config --default "$PKGS_DEFAULT_TYPE" --get pkgs.type)
prefix=$(git config --default "$PKGS_DEFAULT_PREFIX" --get pkgs.prefix)
strategy=$(git config --default "$PKGS_DEFAULT_STRATEGY" --get pkgs.strategy)
message=
all=
depth=-1

while [ $# -gt 0 ]; do
	opt="$1"
	shift
	case "$opt" in
		-q) quiet=1 ;;
		-P) prefix="$1"; shift;;
		-m) message="$1"; shift;;
		-s) strategy="$1"; shift;;
		-d) depth="$1"; shift;;
		--all) all=1 ;;
		--pkg-name) pkg_name="$1"; shift;;
		--pkg-url) pkg_url="$1"; shift;;
		--pkg-type) pkg_type="$1"; shift;;
		--) break ;;
		*) die "Unexpected option: $opt" ;;
	esac
done

command="$1"
shift

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

die() {
    printf '%s\n' "$1" >&2
    exit "${2-1}"
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

pkg_path() {
	path=$1
	[ ! -z $prefix ] && path=$prefix/$path
	echo $path
}

# List packages that were added by "git pkgs add".
get_root_packages() {
	pkg=$1
	revision=$2
	git for-each-ref "refs/pkgs/$pkg/$revision" |
		while read commit type ref; do
			echo $commit
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
	path=$(pkg_path $pkg)
	if [ -d $path ]; then
		git -C $path checkout -q "refs/pkgs/$pkg_name/HEAD/$pkg"
	else
		git worktree add -q -f $path "refs/pkgs/$pkg_name/HEAD/$pkg"
	fi
}

# Hackish, but it works.
is_non_transitive() {
	git name-rev --no-undefined --refs="refs/pkgs/$1/*/$1" "refs/pkgs/$pkg_name/HEAD/$1" &> /dev/null
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
		echo "'git config pkgs.name <name>'"
		die
	fi
}

# Make branch an orphan.
orphanize() {
	src="refs/pkgs/$name/$revision/$name"
	commit=`git rev-parse $src`
	worktree_reset $name

	path=$(pkg_path $name)
	git worktree add -q --no-checkout $path $src

	git -C "$path" checkout -q -f --orphan "$name"
	git -C "$path" -c trailer.ifexists=addIfDifferent commit -C $src -q \
		--trailer "git-pkgs-name:$name" \
		--trailer "git-pkgs-type:$pkg_type" \
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

	pkg=${target#"refs/pkgs/$pkg_name/HEAD/"}
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
		git fetch -f --depth=1 --no-tags $url \
			"$revision:refs/pkgs/$name/$revision/$name" || die

		# Make shallow branch an orphan.
		orphanize
	fi

	echo "From $url"
	echo " * [new package]     $name@$revision"

	# select referenced packages into refs/release/head
	echo "Depencies resolved:"
	git fetch . "refs/pkgs/$name/$revision/*:refs/pkgs/$pkg_name/HEAD/*" --no-tags --porcelain | \
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

	git add .
	git -c trailer.ifexists=addIfDifferent commit -q --allow-empty --message="$message" \
		--trailer "git-pkgs-name:$name" \
		--trailer "git-pkgs-type:$pkg_type" \
		--trailer "git-pkgs-revision:$revision"

	git tag $revision
	git fetch -q . "refs/pkgs/$pkg_name/HEAD/*:refs/pkgs/$name/$revision/*"

	# N: We can not use --depth=1 here. This will make the main branch grafted.
	git fetch -q -f --no-tags . "$revision:refs/pkgs/$name/$revision/$name"

	url=$pkg_url
	[[ $url ]] || echo "warning: could not determine repository url."

	orphanize
	git fetch -q -f . "refs/pkgs/$name/$revision/$name:refs/pkgs/$name/HEAD/$name"
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

	git fetch -q -p -f . "refs/pkgs/$pkg_name/$revision/*:refs/pkgs/$pkg_name/HEAD/*"

	git for-each-ref "refs/pkgs/$pkg_name/HEAD"	--format="%(refname)" |
		while read ref; do
			pkg=${ref#"refs/pkgs/$pkg_name/HEAD/"}
			if [[ $pkg_name != $pkg ]]; then
				worktree_checkout $pkg
			fi
		done
}

# List all (remote) release tags of a package.
cmd_ls-releases() {
	pkg=$1
	[[ $pkg ]] || die "fatal: required argument <pkg> missing."
	url=$(get_trailer "refs/pkgs/$pkg_name/HEAD/$pkg" git-pkgs-url)
	git ls-remote --refs --tags $url
}

# Get status (commit/revision) of all packages.
cmd_status() {
	fmt="%(objectname)    %(contents:trailers:key=git-pkgs-name,key=git-pkgs-revision,valueonly,separator=@)"
	git for-each-ref --format="$fmt" "refs/pkgs/$pkg_name/HEAD"
}

# Push release and dependent packages to a remote.
cmd_push() {
	remote=$1
	[ $remote ] || die "fatal: No remote was provided. Where do you want to push?"
	revision=${2:-$(get_revision)}
	git push -f $remote HEAD $revision "refs/pkgs/*"
}

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
		&& git config pkgs.name $pkg_name \
		&& cmd_checkout $revision
}

cmd_mcp() {
	local metadata="$MCP_COMMAND_METADATA"
	local -a commands=()
	while IFS= read -r name; do
		[ -n "$name" ] && commands+=("$name")
	done < <(printf '%s\n' "$metadata" | jq -r '.commands[].name')

	local tools_json
	tools_json=$(printf '%s\n' "$metadata" | jq -c '
	def option_property:
	  if (.property // "") != "" then .property
	  elif (.long // "") != "" then (.long | sub("^--"; "") | gsub("-"; "_"))
	  elif (.flag // "") != "" then (.flag | sub("^-"; ""))
	  else empty end;

	def normalize_option:
	  (option_property) as $property
	  | select($property != "")
	  | {
	      property: $property,
	      takesValue: (.takesValue // false),
	      required: (.required // false),
	      long: .long,
	      flag: .flag,
	      description: (.description // ""),
	      schema: (
	        if (.takesValue // false) then
	          {type: "string", description: (.description // "")}
	        else
	          {type: ["boolean", "null"], description: (.description // "")}
	        end
	      )
	    };

	def normalize_positional:
	  {
	    property: .name,
	    description: (.description // ""),
	    required: (.required // false),
	    schema: {type: "string", description: (.description // "")}
	  };

	(.globals // []) as $globals
	| .commands
	| map(
	    . as $cmd
	    | (
	        reduce (((($cmd.options // []) | map(normalize_option)) + ($globals | map(normalize_option)))[]) as $opt
	          ({};
	            if ($opt.property // "") == "" or has($opt.property) then .
	            else . + {($opt.property): $opt}
	            end
	          )
	      ) as $opt_map
	    | ($opt_map | to_entries | map(.value)) as $options_all
	    | ($options_all | map(select((.long != null) or (.flag != null)))) as $options_cli
	    | (($cmd.positionals // []) | map(normalize_positional)) as $positionals
	    | {
	        name: $cmd.name,
	        description: $cmd.description,
	        inputSchema: {
	          type: "object",
	          properties: (
	            ($opt_map | to_entries | map({(.key): .value.schema}) | add // {})
	            +
	            ($positionals | map({(.property): .schema}) | add // {})
	            +
	            {stdin: {type: "string", description: ("Optional stdin forwarded to git pkgs " + $cmd.name)}}
	          ),
	          required: (
	            ([$options_all[] | select(.required) | .property] + [$positionals[] | select(.required) | .property]) // []
	          ),
	          additionalProperties: true
	        },
	        cli: {
	          options: $options_cli,
	          positionals: $positionals
	        },
	        metadata: {
	          usage: $cmd.usage,
	          options: $cmd.options,
	          positionals: $cmd.positionals
	        }
	      }
	  )
	')

	while IFS= read -r line; do
		[ -z "$line" ] && continue

		local method
		method=$(printf '%s' "$line" | jq -r '.method // empty' 2>/dev/null)
		[ -z "$method" ] && continue

		local id_json
		id_json=$(printf '%s' "$line" | jq -c '.id // null' 2>/dev/null || printf 'null')

		case "$method" in
			initialize)
				jq -c -n --argjson id "$id_json" '{jsonrpc:"2.0",id:$id,result:{protocolVersion:"2024-11-05",capabilities:{experimental:{},prompts:{listChanged:false},resources:{subscribe:false,listChanged:false},tools:{listChanged:false}},serverInfo:{name:"git-pkgs",version:"0.0.1"}}}'
				;;
			notifications/initialized)
				: # notification, no response required
				;;
			tools/list)
				jq -c -n --argjson id "$id_json" --argjson tools "$tools_json" '{jsonrpc:"2.0",id:$id,result:{tools:$tools}}'
				;;
			resources/list)
				jq -c -n --argjson id "$id_json" '{jsonrpc:"2.0",id:$id,result:{resources:[]}}'
				;;
			prompts/list)
				jq -c -n --argjson id "$id_json" '{jsonrpc:"2.0",id:$id,result:{prompts:[]}}'
				;;
			tools/call)
				local tool_name
				tool_name=$(printf '%s' "$line" | jq -r '.params.name // empty' 2>/dev/null)
				if [ -z "$tool_name" ]; then
					jq -c -n --argjson id "$id_json" '{jsonrpc:"2.0",id:$id,error:{code:-32602,message:"Missing tool name"}}'
					continue
				fi

				local supported=0
				for name in "${commands[@]}"; do
					if [ "$name" = "$tool_name" ]; then
						supported=1
						break
					fi
				done

				if [ $supported -eq 0 ]; then
					jq -c -n --argjson id "$id_json" --arg tool "$tool_name" '{jsonrpc:"2.0",id:$id,error:{code:-32601,message:("Unknown tool: " + $tool)}}'
					continue
				fi

				local tool_entry
				tool_entry=$(printf '%s\n' "$tools_json" | jq -c --arg name "$tool_name" '.[] | select(.name == $name)')
				if [ -z "$tool_entry" ]; then
					jq -c -n --argjson id "$id_json" --arg tool "$tool_name" '{jsonrpc:"2.0",id:$id,error:{code:-32601,message:("Unknown tool: " + $tool)}}'
					continue
				fi

				local call_prep
				call_prep=$(printf '%s\n' "$line" | jq -c --argjson tool "$tool_entry" '
	def truthy:
	  if type == "boolean" then .
	  elif type == "number" then (. != 0)
	  else
	    (tostring | ascii_downcase) as $s
	    | ($s == "true" or $s == "1" or $s == "yes" or $s == "y" or $s == "on")
	  end;

	def flag_for($opt):
	  if $opt.long != null then $opt.long else $opt.flag end;

	def normalize_repo_path($args):
	  ($args.repo_path // ".")
	  | if . == null then "."
	    elif (type == "string") then (if . == "" then "." else . end)
	    else (tostring)
	    end;

	(.params.arguments // {}) as $args
	| if ($args | type) != "object" then
	    {error: "Invalid arguments"}
	  elif ($args | has("args")) then
	    if ($args.args | type) != "array" then
	      {error: "Invalid args"}
	    else
	      {
	        mode: "raw",
	        argv: ($args.args | map(tostring)),
	        stdin: ($args.stdin // ""),
	        stdinProvided: (($args | has("stdin")) and ($args.stdin != null))
	      }
	    end
	  else
	    (reduce $tool.cli.options[] as $opt ({argv: []};
	        ($args[$opt.property]) as $value
	        | if ($opt.takesValue == true) then
	            if $value == null then .
	            else .argv += [flag_for($opt), ($value | tostring)]
	            end
	          else
	            if $value == null then .
	            else if ($value | truthy) then .argv += [flag_for($opt)] else . end
	            end
	          end
	      )) as $after_opts
	    | (reduce $tool.cli.positionals[] as $pos ({argv: $after_opts.argv, errors: []};
	        ($args[$pos.property]) as $value
	        | if $value == null then
	            if $pos.required then .errors += ["Missing required positional: " + $pos.property] else . end
	          else .argv += [($value | tostring)]
	          end
	      )) as $final
	    | if ($final.errors | length) > 0 then
	        {error: ($final.errors | join("; "))}
	      else
	        {
	          mode: "structured",
	          argv: $final.argv,
	          stdin: ($args.stdin // ""),
	          stdinProvided: (($args | has("stdin")) and ($args.stdin != null))
	        }
	      end
	  end
	| . + {repoPath: normalize_repo_path($args)}
	')
				if [ $? -ne 0 ] || [ -z "$call_prep" ]; then
					jq -c -n --argjson id "$id_json" '{jsonrpc:"2.0",id:$id,error:{code:-32602,message:"Invalid arguments"}}'
					continue
				fi

				local error_message
				error_message=$(printf '%s\n' "$call_prep" | jq -r '.error // empty' 2>/dev/null)
				if [ -n "$error_message" ]; then
					jq -c -n --argjson id "$id_json" --arg msg "$error_message" '{jsonrpc:"2.0",id:$id,error:{code:-32602,message:$msg}}'
					continue
				fi

				local stdin_payload
				stdin_payload=$(printf '%s\n' "$call_prep" | jq -r '.stdin // ""')
				local stdin_provided
				stdin_provided=$(printf '%s\n' "$call_prep" | jq -r '.stdinProvided // false')
				local repo_path
				repo_path=$(printf '%s\n' "$call_prep" | jq -r '.repoPath // "."')
				if [ -z "$repo_path" ]; then
					repo_path="."
				fi

				local -a args=()
				while IFS= read -r arg; do
					args+=("$arg")
				done < <(printf '%s\n' "$call_prep" | jq -r '.argv[] | tostring')

				local output
				local status
				if [ "$stdin_provided" = "true" ]; then
					output=$(printf '%s' "$stdin_payload" | git -C "$repo_path" pkgs "$tool_name" "${args[@]}" 2>&1)
					status=$?
				else
					output=$(git -C "$repo_path" pkgs "$tool_name" "${args[@]}" 2>&1)
					status=$?
				fi

				if [ $status -eq 0 ]; then
					jq -c -n --argjson id "$id_json" --arg text "$output" '{jsonrpc:"2.0",id:$id,result:{content:[{type:"text",text:$text}],isError:false}}'
				else
					jq -c -n --argjson id "$id_json" --arg text "$output" --arg exit_code "$status" '{jsonrpc:"2.0",id:$id,result:{content:[{type:"text",text:($text + "\n(exit code: " + $exit_code + ")")}],isError:true}}'
				fi
				;;
			shutdown)
				jq -c -n --argjson id "$id_json" '{jsonrpc:"2.0",id:$id,result:null}'
				break
				;;
			exit)
				break
				;;
			*)
				if [ "$id_json" != "null" ]; then
					jq -c -n --argjson id "$id_json" --arg method "$method" '{jsonrpc:"2.0",id:$id,error:{code:-32601,message:("Method not found: " + $method)}}'
				fi
				;;
		esac
	done
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
				print "."
        for (row = 1; row <= NR; row++) print path[row]
    }'
}

format_pkg() {
	pkg=$1
	revision=$2
	head_commit=$(get_commit "refs/pkgs/$pkg_name/$release/$pkg" 2> /dev/null)

 	if [[ $head_commit == $commit ]]; then
		if is_non_transitive $pkg; then
 			echo -e "\e[1;32m$pkg \e[1;36m$revision\e[0m ✓"
		else
 			echo -e "\e[1;32m$pkg \e[1;36m$revision\e[0m •"
		fi
 	else
 		echo -e "\e[32m$pkg \e[36m$revision\e[0m"
 	fi
}

package_tree() {
	local release=$2
	local revision=$3
	local depth=$4

	local pkg=`get_trailer $commit git-pkgs-name`

	if [[ ! $1 =~ ":$pkg" ]] && [[ $depth != 0 ]]; then

		echo -e "$1:$(format_pkg $pkg $revision)"

		git for-each-ref "refs/pkgs/$pkg/$revision" --format="%(objectname) $(trailers git-pkgs-revision)" |
  		while read commit revision; do
  			package_tree "$1:$pkg@$revision" $release $revision $(($depth-1))
  		done
  fi
}

release_tree() {
	release=$1
	get_root_packages $pkg_name $release |
		while read commit; do
			revision=`get_trailer $commit git-pkgs-revision`
			package_tree "" $release $revision $depth
		done
}

cmd_tree() {
	revision=${1:-"HEAD"}
	commit=$(get_commit "refs/pkgs/$pkg_name/$revision/$pkg_name")

	if [[ $all ]]; then
		release_tree $revision | format_tree
	else
		package_tree "" $revision $revision $depth | format_tree
	fi
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
			if git name-rev --no-undefined --refs="refs/pkgs/$pkg_name/HEAD/$pkg" $ref &> /dev/null; then
				worktree_reset $pkg
				# Delete package from HEAD.
				git update-ref -d "refs/pkgs/$pkg_name/HEAD/$pkg" &> /dev/null
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
		sha=`git rev-parse "refs/pkgs/$pkg_name/HEAD/$name"` || die "fatal: Could not extract commit."
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


# All commands but "clone" and "mcp" require a work tree.
[[ $command != "clone" && $command != "mcp" ]] && require_git_version && . git-sh-setup && require_work_tree

"cmd_$command" "$@"
