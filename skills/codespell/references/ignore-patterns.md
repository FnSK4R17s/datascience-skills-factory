# Managing codespell false positives

codespell matches against a hand-curated dictionary of common misspellings.
On real code it surfaces two classes of false positive:

1. **Project jargon** — product names, abbreviations, domain terms.
2. **Opaque strings** — hashes, UUIDs, Base64 blobs, test fixtures.

Pick the narrowest mechanism that kills the noise.

## Mechanisms, narrowest first

### 1. Inline ignore comment

Scoped to one line. Use sparingly — it leaves a trail in the code.

```python
token = "abcde"  # codespell:ignore abcde
```

```rust
// codespell:ignore hte
let hte = 1;
```

### 2. `--ignore-words-list` (CLI flag, comma-separated)

One-off invocations, not persisted. Rarely the right choice for a repo.

```bash
codespell --ignore-words-list=crate,nd,ba
```

### 3. `--ignore-words` file (persisted, repo-wide)

The scalable option. One lowercased word per line. Points at
`.codespell-ignore-words.txt` via `.codespellrc`.

```
# .codespell-ignore-words.txt
crate
nd
ba
```

**Important:** codespell matches case-insensitively. List words
lowercased only. A word here disables the check for that exact token —
both directions (e.g. adding `nd` means `nd` is never flagged as a typo
for `and`, AND `and` is never rewritten to `nd`).

### 4. `skip` glob (file exclusion)

For generated / vendored / binary content. Config'd in `.codespellrc`.
Prefer this over adding hundreds of noise words.

```ini
[codespell]
skip = .git,node_modules,*.lock,*.min.js,fixtures/**
```

### 5. `ignore-regex` (pattern exclusion)

For shapes rather than individual words. Classic case: git short hashes
and hex blobs.

```ini
[codespell]
ignore-regex = \b[A-Fa-f0-9]{7,}\b
```

## Common false-positive domains

| Domain | Typical false positives | Best mechanism |
|--------|--------------------------|----------------|
| ML / AI | `nd` (dimension suffix), `ue` (uncertainty), token IDs | ignore-words file |
| Rust | `crate`, `crates` (first-class lang term) | ignore-words file |
| Chemistry / bio | Protein sequences, gene names | `ignore-regex` or skip test dirs |
| Cryptography | Hex blobs, Base64, SHA/MD5 | `ignore-regex` |
| Legal text | Archaic spellings (`whilst`, `amongst`) | inline `# codespell:ignore` |
| German / Dutch | `ie`/`ei` patterns | not worth fighting; `skip` that tree |
| Localization files | `.po`, `.xlf` with intentional foreign spellings | `skip` glob |

## When to suppress vs. fix

The default should be **fix the typo**. Add an ignore entry only when:

- The token is a product or project name you control.
- The token is a legitimate term-of-art in the domain.
- The token is generated content (hash, id, fixture payload).

Do **not** add ignores to paper over genuine typos in variable names.
Renaming the variable is always the right answer.

## Upstream docs

- codespell CLI: <https://github.com/codespell-project/codespell>
- Suggested dictionaries: `--builtin clear,rare,informal,usage,code,names`
  (enable cautiously — each layer adds false-positive risk).
