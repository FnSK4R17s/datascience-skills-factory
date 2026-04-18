# qmd Configuration Reference

## Collections

Collections map directory paths to named searchable indexes.

```bash
qmd collection add <path> --name <name>    # register
qmd collection list                         # show all
qmd collection remove <name>                # unregister
```

**Glob patterns:** by default qmd indexes `**/*.md`. For code-heavy repos,
use AST-aware chunking:

```bash
qmd embed --chunk-strategy auto
```

This uses tree-sitter to split `.ts`, `.js`, `.py`, `.go`, `.rs` files at
function/class boundaries instead of arbitrary text positions.

## Context

Context adds descriptive metadata that helps qmd understand collection purpose:

```bash
qmd context add qmd://<collection> "<description>"
qmd context list
```

## Embedding Models

Default: `embeddinggemma-300M-Q8_0` (~300MB, auto-downloaded to `~/.cache/qmd/models/`)

Custom model via environment variable:

```bash
export QMD_EMBED_MODEL="hf:Qwen/Qwen3-Embedding-0.6B-GGUF/..."
qmd embed -f   # must force re-embed after model change
```

## Index Storage

- Location: `~/.cache/qmd/index.sqlite`
- Contains: FTS5 full-text index, vector embeddings, LLM cache
- Safe to delete and rebuild with `qmd embed -f`

## Chunking

Documents split into ~900-token chunks with 15% overlap. The algorithm:
1. Identifies natural break points (headings, code fences, paragraph breaks)
2. Scores boundaries by proximity to target size
3. Preserves code block boundaries

## Scoring Pipeline (hybrid `query` mode)

1. **Query expansion** — LLM generates alternative phrasings
2. **Parallel retrieval** — each variant searches BM25 + vector indexes
3. **RRF fusion** — Reciprocal Rank Fusion (k=60) with top-rank bonuses
4. **Candidate selection** — top 30 advance
5. **LLM reranking** — Qwen3-Reranker assigns relevance scores
6. **Position-aware blending:**
   - Ranks 1-3: 75% retrieval / 25% reranker
   - Ranks 4-10: 60% retrieval / 40% reranker
   - Rank 11+: 40% retrieval / 60% reranker

## Models (all local, auto-downloaded)

| Model | Purpose | Size |
|-------|---------|------|
| embeddinggemma-300M-Q8_0 | Vector embeddings | ~300MB |
| qwen3-reranker-0.6b-q8_0 | Reranking | ~640MB |
| qmd-query-expansion-1.7B-q4_k_m | Query generation | ~1.1GB |

## MCP Server

```bash
qmd mcp                    # stdio (default)
qmd mcp --http             # HTTP on localhost:8181
qmd mcp --http --daemon    # background daemon
qmd mcp stop               # stop daemon
```

Exposed tools: `query`, `get`, `multi_get`, `status`

HTTP mode caches loaded models across requests with 5-minute idle disposal.

## CLI Quick Reference

```bash
# Search
qmd search "keywords"                  # BM25 keyword search
qmd vsearch "natural language"         # vector semantic search
qmd query "complex question"           # hybrid + reranking (best)
qmd query -n 10 --min-score 0.3 "q"   # with limits

# Retrieval
qmd get "path/to/doc.md"              # single document
qmd get "#abc123"                      # by document ID
qmd multi-get "wiki/concepts/*.md"    # batch by glob

# Index management
qmd embed                             # generate/update embeddings
qmd embed -f                          # force full re-embed
qmd update                            # re-scan collections for changes

# Output formats
--json --csv --md --xml --files --full --explain
```
