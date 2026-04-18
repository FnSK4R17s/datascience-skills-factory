# qmd-search

Install [qmd](https://github.com/tobi/qmd) — a local hybrid search engine — and
index markdown knowledge bases for fast agent-accessible search.

## What It Does

qmd combines BM25 keyword search, vector semantic search, and LLM reranking into
a single local tool. No cloud services required. This skill automates setup so
agents can search wikis and docs collections without globbing/grepping hundreds
of files.

## How It Works

### Setup (`/qmd-search`)

When you invoke the skill, Claude will:

1. **Check** prerequisites (Node.js >= 22 or Bun >= 1.0.0)
2. **Install** qmd globally if missing
3. **Detect** markdown collections in the workspace
4. **Register** collections and build the search index (~2GB model download on first run)
5. **Verify** with a test search
6. **Optionally** set up MCP server for agent tool access
7. **Optionally** install a PostToolUse hook for auto-reindexing on writes

### Runtime

Once indexed, agents search with:

```bash
qmd search "keyword query"           # fast keyword search
qmd vsearch "semantic question"      # vector similarity
qmd query "complex question"         # hybrid + reranking (best quality)
```

Or via MCP tools: `query`, `get`, `multi_get`, `status`.

## Installation

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill qmd-search
```

Or invoke directly if loaded:

```
/qmd-search
```

## File Structure

```
qmd-search/
├── SKILL.md                    # Skill entry point (decision tree for Claude)
├── README.md                   # This file
├── scripts/
│   ├── install-qmd.sh          # Installs qmd globally
│   └── update-index.sh         # PostToolUse hook for auto-reindexing
└── references/
    └── qmd-config.md           # Detailed configuration and tuning options
```
