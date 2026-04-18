---
name: qmd-search
description: >
  Search markdown knowledge bases using qmd — a local hybrid search engine
  combining BM25 keywords, vector similarity, and LLM reranking. Use when
  searching a wiki or docs repo, when glob/grep is too slow or imprecise across
  many markdown files, or when the user mentions "qmd", "semantic search",
  "search my wiki", or "knowledge base search".
  Triggers on: "qmd", "search wiki", "semantic search", "wiki search",
  "knowledge base search", "find in wiki", "query wiki".
  For first-time setup, see BOOTSTRAP.md.
---

# qmd-search Skill

Search markdown knowledge bases with qmd. Three search modes, all local,
no cloud services.

## When to Use qmd vs. Grep/Glob

| Situation | Use |
|-----------|-----|
| Know the exact filename or path | Glob / Read |
| Know an exact string or symbol | Grep |
| Natural language question across many files | `qmd query` |
| Fuzzy/semantic "find pages about X" | `qmd vsearch` |
| Keyword search with ranking | `qmd search` |
| Need to retrieve a known doc by path | `qmd get` |

**Rule of thumb:** if you'd need 3+ grep passes to find what you want,
use `qmd query` instead.

## Search Commands

### Keyword Search (BM25)

Fast, exact. Best when you know the terminology:

```bash
qmd search "Kot massacre political fallout"
qmd search "graph traversal algorithm" -n 5
```

### Semantic Search (Vector)

Finds conceptually related content even without keyword overlap:

```bash
qmd vsearch "how did Nepal transition from monarchy to democracy"
qmd vsearch "advantages of planar graphs" -n 10
```

### Hybrid Search (Best Quality)

Combines BM25 + vectors + LLM reranking. Use for complex questions:

```bash
qmd query "what role did the Rana dynasty play in modernizing Nepal"
qmd query "compare BFS and DFS for external memory" --min-score 0.3
```

### Document Retrieval

Fetch specific documents without searching:

```bash
qmd get "wiki/entities/jung-bahadur-rana.md"
qmd get "#abc123"                              # by document ID
qmd multi-get "wiki/concepts/*.md"             # batch by glob
```

## Output Formats

Default output is human-readable. For programmatic use:

```bash
qmd query "question" --json        # structured JSON
qmd query "question" --csv         # CSV with scores
qmd query "question" --md          # markdown table
qmd query "question" --files       # file paths + scores only
qmd query "question" --full        # include full document content
qmd query "question" --explain     # include scoring breakdown
```

## Score Interpretation

| Score | Meaning |
|-------|---------|
| 0.8 - 1.0 | Highly relevant — direct answer likely in this document |
| 0.5 - 0.8 | Moderately relevant — related content, may need synthesis |
| 0.2 - 0.5 | Somewhat relevant — tangential or partial overlap |
| < 0.2 | Low relevance — likely noise, skip unless desperate |

Use `--min-score 0.3` to filter noise on broad queries.

## Index Management

If you've added or changed files and search results seem stale:

```bash
qmd update                  # re-scan collections for new/changed files
qmd embed                   # regenerate embeddings for changed docs
qmd status                  # check collection stats and index health
```

Force full rebuild (rarely needed):

```bash
qmd embed -f
```

### Keeping Git-Backed Collections Fresh

If a collection is a git repo, attach a pull command so `qmd update --pull`
pulls + reindexes in one step:

```bash
qmd collection update-cmd <name> 'git -C <repo-path> stash && git -C <repo-path> pull --rebase --ff-only && git -C <repo-path> stash pop || true'
```

After setup:

```bash
qmd update --pull && qmd embed   # pull latest, then reindex
```

The `|| true` keeps `stash pop` from failing when there's nothing to pop.

## Collection Management

```bash
qmd collection list                              # show indexed collections
qmd collection add <path> --name <name>          # add new collection
qmd collection remove <name>                     # remove collection
qmd context add qmd://<name> "description"       # add collection context
```

## MCP Tools (if MCP server is configured)

When qmd runs as an MCP server, these tools are available:

- **`query`** — hybrid search (same as `qmd query`)
- **`get`** — retrieve single document by path or ID
- **`multi_get`** — batch retrieve by glob pattern
- **`status`** — collection stats and index health

## Tips

- Prefer `qmd query` over `qmd search` when the question is natural language
- Use `--full` when you need document content inline (saves a Read call)
- Use `--explain` to debug why a result ranked high or low
- Chain with `qmd get` to fetch the top result's full content after a search
- For wiki ingests, run `qmd update && qmd embed` after adding new source pages

## Additional Resources

- `references/qmd-config.md` — models, chunking, scoring pipeline, tuning
- `BOOTSTRAP.md` — first-time setup instructions
