---
name: qmd-search
description: >
  Install and configure qmd (local hybrid search engine) for markdown knowledge
  bases. Detects collections, installs qmd, indexes documents, and optionally
  registers an MCP server for agent-accessible search. Use when setting up search
  for a wiki or docs repo, when search is slow across many markdown files, when
  the user mentions "qmd", "semantic search", "index my docs", or "search my wiki".
  Triggers on: "qmd", "index wiki", "search wiki", "semantic search",
  "install qmd", "wiki search", "knowledge base search".
---

# qmd-search Skill

Install qmd, index markdown collections, and optionally wire up the MCP server
so agents can search without globbing/grepping hundreds of files.

## Decision Tree

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

## Search Reference

Once installed, agents can search with:

```bash
# Keyword search (BM25)
qmd search "query terms"

# Semantic search (vector similarity)
qmd vsearch "natural language question"

# Hybrid search (BM25 + vectors + LLM reranking) — best quality
qmd query "complex question about the knowledge base"

# Retrieve specific document
qmd get "wiki/entities/some-entity.md"

# Batch retrieve by glob
qmd multi-get "wiki/concepts/*.md"
```

**Output flags:** `--json`, `--csv`, `--md`, `--xml`, `--files`, `--full`, `--explain`

**Score interpretation:**
- 0.8-1.0: Highly relevant
- 0.5-0.8: Moderately relevant
- 0.2-0.5: Somewhat relevant
- < 0.2: Low relevance

## Additional Resources

- `references/qmd-config.md` — detailed configuration and tuning options
- `scripts/install-qmd.sh` — installs qmd globally
- `scripts/update-index.sh` — incremental re-index hook for PostToolUse
