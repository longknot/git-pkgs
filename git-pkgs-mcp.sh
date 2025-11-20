#!/bin/bash
#
# git-pkgs-mcp.sh: mcp server for git-pkgs.
#
# Copyright (c) 2025 Mattias Andersson <mattias@longknot.com>.

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

declare -a commands=()
while IFS= read -r name; do
  [ -n "$name" ] && commands+=("$name")
done < <(printf '%s\n' "$MCP_COMMAND_METADATA" | jq -r '.commands[].name')

tools_json=$(printf '%s\n' "$MCP_COMMAND_METADATA" | jq -c '
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
