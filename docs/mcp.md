# Using the git-pkgs MCP server

`git pkgs mcp` exposes the git-pkgs CLI as a Model Context Protocol (MCP) server over stdio. Any MCP-capable agent can discover the full command catalog, structured arguments, and metadata that the script publishes, allowing assistants and IDE integrations to invoke git-pkgs subcommands safely.

This guide shows how to wire the server into popular MCP clients and outlines agentic workflows that pair well with git-native dependency management.

## Prerequisites
- git >= 2.41 (matching the git-pkgs requirement)
- `git-pkgs.sh` copied somewhere on your PATH so `git pkgs` resolves
- An MCP client that can launch stdio-based servers

To verify the server locally, run:
```bash
git pkgs mcp
```
You should see the process wait for JSON-RPC input. Press `Ctrl+C` to exit.

## Client configurations

### GitHub Copilot (VS Code)
Create or update `.vscode/mcp.json` in your workspace:
```json
{
  "servers": {
    "git-pkgs": {
      "command": "git",
      "args": ["pkgs", "mcp"]
    }
  }
}
```
Reload Copilot Chat and the `git-pkgs` namespace should appear in the **Tools** panel.

### Codex (VS Code or CLI)
Add the server to your Codex configuration (usually `~/.codex/config.toml` or `.codex/config.toml` inside the repo):
```toml
[mcp_servers.git-pkgs]
command = "mcplaunch"
args = ["git", "pkgs", "mcp"]
```
Codex launches MCP servers through `mcplaunch`, which supervises process lifecycle and restarts the server when the session ends.

### Continue (VS Code)
Drop a configuration file in `~/.continue/mcpServers/git-pkgs.yaml`:
```yaml
name: git-pkgs
version: 0.0.1
schema: v1
mcpServers:
  - name: git-pkgs
    schema: 0.2.0
    command: "git"
    args:
      - "pkgs"
      - "mcp"
    type: stdio
```
Restart Continue; the assistant will pick up the `git-pkgs` toolset automatically.

### Other MCP clients
Any MCP host that understands stdio transports can run the server with:
```
command: git
args:
  - pkgs
  - mcp
transport: stdio
```
Make sure the working directory points to the repo you want to manage; git-pkgs needs access to its `.git` directory and configuration.

## What the MCP server exposes
- **Command catalog** — Each git-pkgs subcommand is published with usage, option metadata, and argument schemas.
- **Structured invocation** — Clients can call commands with key-value arguments; the server builds the proper CLI invocation and returns stdout/stderr.
- **Tool discovery** — Assistants can list available tools (`tools/list`) and render inline help without scraping shell output.

Inspect the schema by connecting with a generic MCP inspector (e.g., `mcptest`) and invoking `tools/list`.

## Agentic workflows with git-pkgs + MCP
- **Dependency concierge** — Let an LLM agent add or update dependencies via `git pkgs add`, resolve conflicts interactively (`--strategy interactive`), and summarize resulting trees without touching your working copy manually.
- **Release shepherding** — Automate tagging, releasing, and pushing (`git pkgs release`, `git pkgs push`) as part of chat-driven release checklists. The agent can verify `git pkgs status` before finalizing a release.
- **Audit and provenance checks** — Configure an assistant to run `git pkgs show` and `git pkgs tree --all` when reviewing pull requests, ensuring dependency changes are intentional and traceable.
- **CI triage helper** — Point a deployment assistant at failure logs; it can reproduce release state with `git pkgs checkout` and suggest remediation steps.
- **JSON manifest workflows** — Use the agent to export manifests (`git pkgs json-export`) before larger refactors, or to import curated dependency sets into freshly cloned repos.

By combining git-pkgs’ git-native dependency model with MCP-aware agents, teams can keep the entire dependency lifecycle — discovery, upgrades, releases, and audits — within collaborative chat experiences while preserving deterministic, serverless workflows.
