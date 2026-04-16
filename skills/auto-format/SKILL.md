---
name: auto-format
description: >
  Install and configure code formatters (Python, JavaScript/TypeScript, Rust)
  based on project type. Detects project languages from config files, installs
  missing formatters, generates config templates, and sets up a PostToolUse hook
  for automatic formatting on every file write. Use when setting up a new project,
  when formatters are missing or misconfigured, when the user asks about code
  formatting, or when you detect unformatted code in the project.
  Triggers on: "setup formatters", "install formatter", "auto-format",
  "code formatting", "prettier", "ruff", "rustfmt", "black".
---

# Auto-Format Skill

Detect project languages, install formatters, generate configs, and wire up
a PostToolUse hook so every file write is automatically formatted.

## Decision Tree

### 1. Detect Project Languages

Scan the working directory for language signals:

| Signal file         | Language           | Formatter        |
|---------------------|--------------------|------------------|
| `pyproject.toml`    | Python             | ruff             |
| `setup.py`          | Python             | ruff             |
| `requirements.txt`  | Python             | ruff             |
| `*.py`              | Python             | ruff             |
| `package.json`      | JavaScript/TypeScript | prettier      |
| `tsconfig.json`     | TypeScript         | prettier         |
| `deno.json`         | TypeScript         | deno fmt         |
| `Cargo.toml`        | Rust               | rustfmt          |

Report which languages were detected and which formatters are needed.

### 2. Check Installed Formatters

For each detected language, verify the formatter is available:

- **Python**: `ruff --version` (fallback: `black --version`)
- **JS/TS**: `npx prettier --version` or `bunx prettier --version`
- **Rust**: `rustfmt --version` (ships with rustup)

If missing, run `scripts/install-formatters.sh` with the appropriate flags.
The script handles installation via pip, npm/bun, and rustup respectively.

### 3. Generate Config Files (if missing)

For each detected language without an existing formatter config:

- **Python** (no `[tool.ruff]` in pyproject.toml and no `ruff.toml`):
  Copy `assets/ruff.toml` template to project root.

- **JS/TS** (no `.prettierrc*` and no `prettier` key in package.json):
  Copy `assets/.prettierrc` template to project root.

- **Rust** (no `rustfmt.toml` and no `.rustfmt.toml`):
  Copy `assets/rustfmt.toml` template to project root.

Always show the user what config was generated and let them adjust before committing.

### 4. Install the PostToolUse Hook

Check if `~/.claude/settings.json` already has an auto-format hook.
If not, add the following hook configuration:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_SKILL_DIR}/scripts/auto-format.sh"
          }
        ]
      }
    ]
  }
}
```

If other PostToolUse hooks exist, merge — do not replace.

### 5. Verify

After setup, test by editing a file and confirming formatting runs automatically.
Report which formatters are active and what hook was installed.

## Additional Resources

- `references/formatter-config.md` — detailed config options for each formatter
- `scripts/auto-format.sh` — the hook script that runs after every Edit/Write
- `scripts/install-formatters.sh` — installs missing formatters
- `assets/ruff.toml` — Python formatter config template
- `assets/.prettierrc` — JS/TS formatter config template
- `assets/rustfmt.toml` — Rust formatter config template
