<p align="center">
  <img src="logo.png" alt="OpenTUI" height="88">
</p>

<h3 align="center">OpenTUI</h3>

<p align="center">
  <strong>Build rich terminal UIs on a native Zig core.</strong><br>
  <sub>By <a href="https://anomaly.co">Anomaly</a> &mdash; powers OpenCode and terminal.shop in production.</sub>
</p>

---

> **External skill** — not maintained by this repository.
> See [anomalyco/opentui](https://github.com/anomalyco/opentui) for docs and support.

## What it does

Teaches Claude to build performant terminal user interfaces using the OpenTUI
library (TypeScript/Bun). Covers the core renderer, Yoga-powered flexbox
layout, keyboard/focus management, React and Solid JSX bindings, the plugin
system, animation timeline API, and built-in components.

The skill uses a lazy-loading routing table — `SKILL.md` points Claude at
sibling `.mdx` docs on demand rather than inlining everything.

## Install

```bash
npx skills add anomalyco/opentui --skill opentui --global
```

## Links

- Website: [opentui.com](https://opentui.com/)
- Repository: [github.com/anomalyco/opentui](https://github.com/anomalyco/opentui)
