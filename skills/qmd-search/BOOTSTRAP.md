# BOOTSTRAP.md — First-Time qmd Setup

One-time setup flow. After completing these steps, delete this file and use
SKILL.md for day-to-day search operations.

## Steps

### 1. Check Prerequisites

Verify Node.js >= 22 or Bun >= 1.0.0 is available:

```bash
node --version   # must be >= 22
bun --version    # alternative: >= 1.0.0
```

If neither is available, stop and tell the user.

### 2. Install qmd

Check if qmd is already installed:

```bash
qmd --version
```

If missing, run `scripts/install-qmd.sh`. The script installs globally via
npm or bun depending on what's available.

### 3. Detect Collections

Scan the working directory and any additional working directories for markdown
knowledge bases. A collection candidate is any directory containing 10+ `.md`
files (excluding `node_modules`, `.git`, `.obsidian`).

Common patterns:

| Directory pattern       | Likely collection name |
|------------------------|----------------------|
| `wiki/`                | `<repo-name>-wiki`  |
| `docs/`                | `<repo-name>-docs`  |
| `notes/`               | `<repo-name>-notes` |
| `raw/`                 | `<repo-name>-raw`   |
| Root with many `.md`   | `<repo-name>`       |

Present detected collections to the user and ask which to index.

### 4. Register Collections

For each confirmed collection:

```bash
qmd collection add <path> --name <collection-name>
```

### 5. Add Context (Optional)

If the collection has a README, CLAUDE.md, or similar overview file, register
it as context so qmd understands the collection's purpose:

```bash
qmd context add qmd://<collection-name> "<one-line description>"
```

### 6. Build Index

Run the embedding pipeline. This downloads models (~2GB) on first run:

```bash
qmd embed
```

For large collections (500+ files), warn the user this may take a few minutes.

To force a full re-index:

```bash
qmd embed -f
```

### 7. Verify

Run a test search against indexed content:

```bash
qmd search "test query relevant to collection" --json
```

Confirm results are returned and scores look reasonable. Report the collection
stats (document count, chunk count) via:

```bash
qmd status
```

### 8. MCP Server Setup (Optional)

Ask the user if they want MCP integration for agent access. If yes:

**For Claude Code** — add to `.claude/settings.json` (project-level) or
`~/.claude/settings.json` (global):

```json
{
  "mcpServers": {
    "qmd": {
      "command": "qmd",
      "args": ["mcp"]
    }
  }
}
```

**For daemon mode** (persistent, shared across sessions):

```bash
qmd mcp --http --daemon
```

This exposes tools: `query`, `get`, `multi_get`, `status`.

### 9. Update Hook (Optional)

If the collection is actively edited (e.g., a wiki that grows during sessions),
offer to set up an update hook so new/changed files are re-indexed:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_SKILL_DIR}/scripts/update-index.sh"
          }
        ]
      }
    ]
  }
}
```

If other PostToolUse hooks exist, merge — do not replace.

## Done

Once setup is verified, delete this file — you won't need it again.
Use SKILL.md for search operations going forward.
