<p align="center">
  <img src="logo.png" alt="tdd" height="88">
</p>

<h1 align="center">tdd</h1>

<p align="center">
  <strong>Red-Green-Refactor TDD discipline as context for the agent. No enforcement, no state, no cost.</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

> Adapted from [mattpocock/skills/tdd](https://github.com/mattpocock/skills/tree/main/tdd) (MIT). Soft skill — the agent reads SKILL.md and follows the discipline. The skill carries no hooks, no guard scripts, no phase state, and nothing that can break the user's project. If the agent doesn't follow the discipline, that's a prompt problem, not a tooling problem.

## What this ships

| File | Purpose |
|------|---------|
| [SKILL.md](SKILL.md) | Entry — philosophy, anti-horizontal-slice warning, tracer-bullet workflow, per-cycle checklist, subagent dispatch guidance |
| [BOOTSTRAP.md](BOOTSTRAP.md) | First-time setup — copy subagent files to a Claude Code discovery path (looked up via the `claude-docs` skill) |
| [REWARD_HACKING.md](REWARD_HACKING.md) | Main-agent audit checklist — what to look for in each subagent's report before accepting and moving to the next phase |
| [agents/tdd-red.md](agents/tdd-red.md) | Subagent — RED phase. Writes ONE failing test for one user-visible behavior. |
| [agents/tdd-green.md](agents/tdd-green.md) | Subagent — GREEN phase. Writes MINIMUM production code to make the failing test pass. |
| [agents/tdd-refactor.md](agents/tdd-refactor.md) | Subagent — REFACTOR phase. Improves production structure; tests stay green. No new tests, no behavior changes. |
| [references/tests.md](references/tests.md) | Good vs bad tests with TS examples; integration-style as default; warning signs of implementation-coupled tests |
| [references/mocking.md](references/mocking.md) | Mock at system boundaries only; designing interfaces for mockability via dependency injection and SDK-style APIs |
| [references/deep-modules.md](references/deep-modules.md) | "A Philosophy of Software Design" — small interface + deep implementation |
| [references/interface-design.md](references/interface-design.md) | Three rules: accept dependencies, return results not side effects, small surface area |
| [references/refactoring.md](references/refactoring.md) | Refactor candidates checklist for the post-GREEN cleanup pass |
| [assets/python-pytest.md](assets/python-pytest.md) | Stack adapter — pytest 9.x, pytest-asyncio, FastAPI TestClient + httpx.AsyncClient. Verified end-to-end. |
| [assets/typescript-vitest.md](assets/typescript-vitest.md) | Stack adapter — vitest 4.x, Testing Library + userEvent for React, supertest for backend. Verified end-to-end. |
| [assets/typescript-playwright.md](assets/typescript-playwright.md) | Stack adapter — Playwright 1.59 for E2E browser tests. Config + spec syntax verified; browser execution requires `npx playwright install`. |

## When the skill triggers

Reads its own SKILL.md frontmatter. Fires on: "TDD", "red-green-refactor", "test-first", "write a failing test", "test-driven", "integration tests".

## Usage

There is no `/tdd-init`, `/tdd-start`, or any slash command. The agent reads SKILL.md and runs the cycle:

1. **Plan** — confirm interface + which behaviors matter most. Get user approval.
2. **Tracer bullet** — one test → one minimum implementation.
3. **Incremental loop** — one more test → one more minimum impl. Repeat.
4. **Refactor** — only after all tests pass. Tests stay green.

The skill prevents you from writing all tests up front (the "horizontal slice" anti-pattern) by repeatedly reminding the agent to write ONE test at a time and let what you learn from each cycle shape the next.

## Why no enforcement

We tried building enforcement (PreToolUse hook + AST guard + state machine + scoped subagents) — the previous version of this skill. The result was 50KB of code, three bugs in the first end-to-end test, and the headline feature (lock test files in GREEN) didn't work. Threw it away.

mattpocock's approach — trust + checklist — is 9.6KB of markdown and works. See [ANTIPATTERNS.md](../../ANTIPATTERNS.md) AP1, AP2, AP4 in the repo root for the postmortem.

## Files

```
skills/tdd/
├── SKILL.md
├── README.md                (this file)
├── BOOTSTRAP.md             (one-time: look up discovery path via claude-docs, then copy subagents)
├── REWARD_HACKING.md        (main-agent audit checklist for each phase report)
├── logo.png
├── agents/
│   ├── tdd-red.md           (RED-phase subagent)
│   ├── tdd-green.md         (GREEN-phase subagent)
│   └── tdd-refactor.md      (REFACTOR-phase subagent)
├── assets/
│   ├── python-pytest.md         (verified against pytest 9.0.3, fastapi 0.136, httpx 0.28)
│   ├── typescript-vitest.md     (verified against vitest 4.1.5, RTL, supertest, Node 24)
│   └── typescript-playwright.md (config + spec syntax verified against @playwright/test 1.59.1)
└── references/
    ├── tests.md
    ├── mocking.md
    ├── deep-modules.md
    ├── interface-design.md
    └── refactoring.md
```

## Install

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill tdd
```
