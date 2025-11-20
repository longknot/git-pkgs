#!/bin/bash
# Install git-pkgs and its helper scripts into the git exec-path.

# check requirements
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
command -v git >/dev/null || { echo "git is required" >&2; exit 1; }

# copy git-pkgs to where the rest of the git scripts are found.
chmod +x git-pkgs.sh
chmod +x git-pkgs-mcp.sh
cp -ax git-pkgs.sh "$(git --exec-path)/git-pkgs"
cp -ax git-pkgs-mcp.sh "$(git --exec-path)/git-pkgs-mcp"

echo "Installation complete. You can now use 'git pkgs' and 'git pkgs-mcp' commands."