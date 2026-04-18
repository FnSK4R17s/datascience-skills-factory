<h1 align="center">🎨🏭 auto-format</h1>

<p align="center">
  <strong>Automatic code formatting on every file write.</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

Detect project languages, install formatters, and wire up automatic formatting so every file Claude writes is formatted on save — no prompting required.

## Supported Languages

| Language | Formatter | Config template |
|----------|-----------|-----------------|
| Python | [ruff](https://docs.astral.sh/ruff/) (fallback: black) | `assets/ruff.toml` |
| JavaScript / TypeScript | [prettier](https://prettier.io/) | `assets/.prettierrc` |
| Rust | [rustfmt](https://rust-lang.github.io/rustfmt/) | `assets/rustfmt.toml` |

## How It Works

This skill has two parts: a **setup flow** and a **runtime hook**.

### Setup (`/auto-format`)

When you invoke the skill, Claude will:

1. **Detect** which languages your project uses (via `pyproject.toml`, `package.json`, `Cargo.toml`, etc.)
2. **Install** missing formatters using the appropriate package manager
3. **Generate** config files from the bundled templates (only if no config exists)
4. **Register** a `PostToolUse` hook in `~/.claude/settings.json` that runs `scripts/auto-format.sh` after every `Edit` or `Write`

### Runtime (`auto-format.sh`)

Once the hook is installed, formatting is fully automatic and deterministic — no LLM involvement. The hook:

- Reads the edited file path from the tool event
- Routes to the correct formatter by file extension
- Silently skips if the formatter isn't installed
- Always exits 0 so edits are never blocked

## Installation

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill auto-format
```

Or invoke directly if the skill is already loaded:

```
/auto-format
```

## Manual formatter install

The bundled install script can also be run standalone:

```bash
# Auto-detect from project files
./scripts/install-formatters.sh --detect

# Specific languages
./scripts/install-formatters.sh --python --js

# Everything
./scripts/install-formatters.sh --all
```

## File Structure

```
auto-format/
├── SKILL.md                    # Skill entry point (decision tree for Claude)
├── README.md                   # This file
├── scripts/
│   ├── auto-format.sh          # PostToolUse hook — runs after every Edit/Write
│   └── install-formatters.sh   # Installs missing formatters
├── references/
│   └── formatter-config.md     # Detailed config options per formatter
└── assets/
    ├── ruff.toml               # Python config template
    ├── .prettierrc             # JS/TS config template
    └── rustfmt.toml            # Rust config template
```
