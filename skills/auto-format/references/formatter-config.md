# Formatter Configuration Reference

## Python — ruff

Ruff is the recommended Python formatter. It replaces black + isort + flake8 in a single tool.

### Config locations (precedence order)
1. `ruff.toml` or `.ruff.toml` in project root
2. `[tool.ruff]` section in `pyproject.toml`

### Key settings

```toml
# ruff.toml
line-length = 88              # black-compatible default
target-version = "py311"       # minimum Python version

[format]
quote-style = "double"         # "single" or "double"
indent-style = "space"         # "space" or "tab"
docstring-code-format = true   # format code in docstrings

[lint]
select = ["E", "F", "I", "UP"] # pycodestyle, pyflakes, isort, pyupgrade
```

### Common overrides
- `line-length = 120` — wider lines for data science / notebooks
- `[lint.per-file-ignores] "tests/**" = ["S101"]` — allow assert in tests
- `[lint.isort] known-first-party = ["mypackage"]` — isort grouping

### CLI usage
```bash
ruff format .              # format all files
ruff check --fix .         # lint + auto-fix
ruff format --check .      # CI: check without writing
```

---

## JavaScript/TypeScript — prettier

### Config locations (precedence order)
1. `.prettierrc` / `.prettierrc.json` / `.prettierrc.yml`
2. `.prettierrc.js` / `prettier.config.js`
3. `"prettier"` key in `package.json`

### Key settings

```json
{
  "semi": true,
  "singleQuote": true,
  "tabWidth": 2,
  "trailingComma": "es5",
  "printWidth": 80,
  "arrowParens": "always",
  "endOfLine": "lf"
}
```

### Ignore patterns
Create `.prettierignore` (follows .gitignore syntax):
```
dist/
build/
coverage/
*.min.js
```

### CLI usage
```bash
npx prettier --write .         # format all
npx prettier --check .         # CI: check without writing
npx prettier --write "src/**/*.{ts,tsx}"  # specific glob
```

### Plugin ecosystem
- `prettier-plugin-tailwindcss` — sort Tailwind classes
- `prettier-plugin-organize-imports` — auto-sort imports
- `@trivago/prettier-plugin-sort-imports` — custom import order

---

## Rust — rustfmt

### Config locations
1. `rustfmt.toml` in project root
2. `.rustfmt.toml` in project root

### Key settings

```toml
# rustfmt.toml
edition = "2021"
max_width = 100
tab_spaces = 4
use_small_heuristics = "Default"
```

### Stable vs nightly options
Most options require nightly rustfmt. Stable options:
- `max_width`
- `hard_tabs`
- `tab_spaces`
- `edition`
- `use_small_heuristics`

Nightly-only (use `#![rustfmt::skip]` attribute as alternative):
- `imports_granularity`
- `group_imports`
- `wrap_comments`

### CLI usage
```bash
rustfmt src/main.rs            # format single file
cargo fmt                      # format entire project
cargo fmt -- --check           # CI: check without writing
```

---

## Hook behavior notes

The `auto-format.sh` hook:
- Runs after every `Edit` and `Write` tool call
- Detects language by file extension, not project config
- Silently skips if formatter is not installed (exit 0)
- Uses `--quiet` flags to minimize output noise
- For ruff: runs both `format` and `check --fix` (lint auto-fixes)
- For prettier: prefers `bunx` over `npx` if bun is available
- For rustfmt: defaults to `--edition 2021`
