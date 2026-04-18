# Fluent 3D Emoji — Folder Name Mapping

Maps Unicode emoji to their Microsoft Fluent Emoji 3D asset folder names.
Used by `scripts/generate-logo.sh` to download the correct PNGs.

Source: https://github.com/microsoft/fluentui-emoji/tree/main/assets

## Currently Used

| Emoji | Unicode | Fluent Folder | Used By |
|-------|---------|---------------|---------|
| 🏭 | U+1F3ED | Factory | Base mark (all skills) |
| 📊 | U+1F4CA | Bar chart | Repo logo |
| 🔬 | U+1F52C | Microscope | Repo logo |
| ✨ | U+2728 | Sparkles | Repo logo |
| 🎨 | U+1F3A8 | Artist palette | auto-format |
| 📡 | U+1F4E1 | Satellite antenna | langfuse-tracing |
| 📋 | U+1F4CB | Clipboard | prd-karpathy-style |
| 🔍 | U+1F50D | Magnifying glass tilted left | qmd-search |
| 🎪 | U+1F3AA | Circus tent | brand-kit |

## Good Candidates for Future Skills

| Emoji | Fluent Folder | Good For |
|-------|---------------|----------|
| 🧪 | Test tube | Testing, experiments |
| 🧬 | Dna | Bioinformatics, genetics |
| 📈 | Chart increasing | Metrics, growth |
| 🗄️ | File cabinet | Storage, databases |
| 🔧 | Wrench | Config, tooling |
| 🧠 | Brain | ML, AI, intelligence |
| 🌐 | Globe with meridians | Web, APIs, networking |
| 📦 | Package | Packaging, deployment |
| 🔗 | Link | Integration, connectors |
| ⚡ | High voltage | Performance, speed |
| 🛡️ | Shield | Security |
| 📝 | Memo | Documentation, notes |
| 🎯 | Direct hit | Targeting, precision |
| 🔄 | Counterclockwise arrows button | Sync, pipelines |
| 🏗️ | Building construction | Infrastructure, scaffolding |

## How to Find New Emoji Folders

1. Browse https://github.com/microsoft/fluentui-emoji/tree/main/assets
2. Find the emoji by its English name
3. Verify the `3D/` subfolder exists (some emoji only have flat or color variants)
4. The PNG filename is the folder name in snake_case + `_3d.png`

Example: "Magnifying glass tilted left" → `magnifying_glass_tilted_left_3d.png`
