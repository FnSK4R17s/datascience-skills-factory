# Anti-patterns

Append-only log of mistakes agents have made in this repo and the correct
approach. **Newest first.** Read this file before starting non-trivial work.

Format per entry:

```
## <YYYY-MM-DD> — <one-line summary>

**What went wrong:** <what the agent did>

**Correct approach:** <what to do instead>

**Context:** <optional — file path, command, or scenario>
```

Use `${CLAUDE_SKILL_DIR}/scripts/log-antipattern.sh` (from the
`repo-best-practices` skill) to append entries — keeps formatting consistent
and ordering correct.

---

<!-- New entries go below this line, newest first. -->

## 2026-04-23 — Subagent worktrees starved of gitignored inputs

**What went wrong:** Spawned four parallel subagents in fresh worktrees (`git worktree add -b feat/<slug>-skill`) and told each to read its source material from `plan/<slug>/docs/`. The worktree was branched from `main`, and `plan/*/docs/` is gitignored (matches `docs/` in `.gitignore`), so the worktree was empty for that path. Agents could not see the 31-336 scraped doc files. Instead of stopping and escalating, all four agents silently fell back to training knowledge of the target libraries and shipped skills built from memory. For v1 APIs that had just released, that memory is stale. The orchestrator did not notice until a spot-check — one agent had mentioned the missing docs in its report, but the others just reported success.

**Correct approach:** Worktrees isolate **writes**, not **inputs**. Never rely on relative paths inside a worktree for input that is not tracked. Pass the absolute path to the source-of-truth location on the host filesystem (`/apps/<repo>/plan/<slug>/docs/`) so worktrees and the main checkout read the same bytes. When a subagent discovers a required input is missing, it must abort with an error — not silently downgrade to training knowledge. Orchestrators: before spawning, verify that every input path named in the prompt exists from the agent's perspective (i.e., inside the worktree, not the main checkout).

**Context:** `feat/{langchain,langgraph,mcp-python-sdk,python-telegram-bot}-skill` branches, commits `46f244e` / `122fde7` / `98134a9` / `4221875`. `.gitignore` line: `docs/`. Detected after merge + push; re-run required, pointing subagents at absolute `/apps/datascience-skills-factory/plan/<slug>/docs/`.

---

## 2026-04-22 — Skill prescribed implementation instead of pointing at the problem

**What went wrong:** Shipped `gpl-license-checker` as a 400-line Python stack (registry lookups, license-string normalizer, markdown-policy parser, SPDX classifier, shell wrapper, PreToolUse hook). Every layer rots independently and the ecosystem (PyPI / npm / crates / GitHub) keeps changing the fields it exposes — each drift needs a patch to the shipped code. The skill also froze one particular solution into place: future agents hitting this file are now reading my Python instead of solving the problem in whatever way is best at the time they read it. Worse, the first "fix" I wrote for this entry doubled down: "ship a script only when..." — turning the lesson into another prescription.

**Correct approach:** A skill defines the problem and points at where to look. State the goal, list authoritative sources, record the empirical traps seen in the wild (as reference data, not as required algorithms), and stop. Leave the implementation decision to the agent invoking the skill — it is, on average, smarter than the one that wrote the skill, and strictly smarter than the one that will write it next year. Reference data is durable (SPDX lists, quirk catalogues, known cross-source disagreements); implementation is not.

**Context:** `skills/gpl-license-checker/scripts/check_package.py` and siblings replaced with `skills/gpl-license-checker/check-package.md` + `references/known-quirks.md`. Policy remains in `references/policy.md`. Compounding lesson: when migrating, translate first, delete second — I deleted the Python before writing the markdown and lost roughly half the empirical detail from memory. Restored via `git checkout HEAD --` and then re-translated with the source in view.

---


## 2026-04-22 — Ship without end-to-end test

**What went wrong:** 50KB skill passed 2 unit smoke tests proving script parses, not that system enforces what docs claim. First real R-G-R cycle: GREEN didn't lock tests. Headline feature dead.

**Correct approach:** Run full user flow in fresh `/tmp` project before claiming "works". Unit tests are sanity check, not validation.

**Context:** tdd skill.

## 2026-04-22 — Surface complexity ≠ value

**What went wrong:** Built 50KB skill with hooks + AST + state machine that breaks, while competitor ships 9.6KB markdown that works.

**Correct approach:** If competitor is 1/5 your size, justify the extra in one sentence or delete it.

**Context:** tdd vs mattpocock/tdd.

## 2026-04-22 — Hard gates without escape

**What went wrong:** Strict transition preconditions ("can't go A→B without X") trapped users. Only escape was destructive reset or faking the precondition (reward-hack).

**Correct approach:** Every gate gets an escape command documented next to it. Block writes (real anti-cheat); warn on phase claims (cheap to undo). Forward gates need backward commands that preserve context.

**Context:** tdd R4. Test passed in RED → can't go GREEN, can't go back (R2 locked tests), only escape was reset (lose slice).

## 2026-04-22 — Documented features that don't exist

**What went wrong:** Doc claimed "X is blocked" but code didn't block X. Users trust doc; first slip kills trust.

**Correct approach:** Every "X is enforced" claim points to a code line + test exercising both fire and no-fire. Can't point? Implement or delete the claim.

**Context:** tdd ANTIPATTERNS.md "AP12: hard retry budget MAX_RETRIES=3". No retry budget existed — wishlist disguised as feature.

## 2026-04-22 — Hardcoded skill-location math

**What went wrong:** `<skill>/../../agents/` assumed skill at `<root>/.claude/skills/<name>/`. From a dev checkout, files would land in a garbage location silently.

**Correct approach:** Print resolved target before any copy. Validate with `realpath`. Reject if not under expected ancestor.

**Context:** tdd INSTALL.md step 2. Would have written agents to `/apps/datascience-skills-factory/agents/` from checkout.

## 2026-04-22 — Inconsistent path keys in shared state

**What went wrong:** State file accumulated entries by path. One code path wrote absolute, another wrote relative. Same file, two keys. Lookups silently missed.

**Correct approach:** Pick one form (relative-to-project-root). Normalize at every read AND every write. Add test that writes via one form, reads via other, asserts match.

**Context:** tdd `state.test_counts` had both `tests/test_x.py` and `/tmp/proj/tests/test_x.py` for the same file.

## 2026-04-22 — "Works in unit tests" syndrome

**What went wrong:** Hand-crafted JSON payloads ≠ real Claude Code payloads (missing keys, edge-case quoting, paths needing resolution). Script "worked" in isolation, fell over in use. Cascade bugs invisible until forced.

**Correct approach:** Unit test = sanity check. Validation = one cycle in fresh project with hooks wired through real `settings.json`, exercising user-facing slash commands.

**Context:** tdd smoke tests across INSTALL/BOOTSTRAP/`/tdd-init` all hand-crafted JSON. None ran real R-G-R.

## 2026-04-22 — Two install modes before one works

**What went wrong:** Shipped user-level + project-level + dispatcher + scope decision at once. Both modes shared the same bugs. Test surface doubled, time per mode halved.

**Correct approach:** Pick simpler scope (usually project). Ship that. Add second mode after first runs in N projects without surprise.

**Context:** tdd went straight to dual-scope. Three rounds of refactoring before first end-to-end test; test exposed bugs in both modes equally.

## 2026-04-22 — Orchestration shell scripts hide work

**What went wrong:** `bootstrap.sh` / `install.sh` / `run_tests.sh` bundled 10–20 commands. Failure mid-flow was silent or compounded. Agent couldn't intervene. Re-run errored or made things worse.

**Correct approach:** Markdown-driven install. One step = one observable op the agent verifies. Reserve shell only for hook dispatch.

**Context:** tdd v1 had 5 wrapper scripts. User flagged as liability; ate multiple refactor rounds.

## 2026-04-22 — Trigger keyword spam

**What went wrong:** Frontmatter description listed every keyword imaginable so the skill always fired — including on tasks it couldn't do. Discovery system trust died.

**Correct approach:** Triggers = words user types when they specifically want THIS skill. Overlap with another skill? Narrow both. More than 6 keywords? Reaching.

**Context:** tdd skill frontmatter.

## 2026-04-22 — Recommend untested tools

**What went wrong:** Doc said "compose with X" / "you could use Y", but X and Y were never installed. Third-party version of "documented features that don't exist".

**Correct approach:** No recommendation without an end-to-end run in the same composition. No working example → delete the line.

**Context:** tdd README "compose nizos/tdd-guard". Never installed. Cargo-cult name-drop.

## 2026-04-22 — Touch user's global Claude config without permission

**What went wrong:** Wrote `~/.claude/` (settings.json, skills/, agents/, commands/, hooks/, CLAUDE.md) without explicit in-message OK. Machine-wide config — breaks every project, not just this one. Backup-and-restore doesn't make it safe; backups fail.

**Correct approach:** Testing goes to `/tmp/<scratch>/` or project-local `.claude/`. Need a user-scope write? Stop, name the path, wait for yes. "I'll restore it" is not consent. "Just to check discovery" is the common excuse — user can install themselves.

**Context:** tdd build session. Copied skill to `~/.claude/skills/tdd/`, agents to `~/.claude/agents/`, backed up + restored `~/.claude/settings.json`. User caught a second instance and called it dangerous — correctly.

## 2026-04-22 — Hardcode live docs instead of deferring to lookup skill

**What went wrong:** Snapshotted path / version / API into static markdown despite a dedicated lookup skill (`claude-docs`, `vercel:*`) existing. User had said "let the agent look it up" — hardcoding overrode the instruction and removed the lookup skill from the loop. Snapshot rots; agent follows stale path forever.

**Correct approach:** Defer — "use the `claude-docs` skill to find X", not "X is at Y". Static docs are for stable contracts only (this skill's own behavior). External-project paths are never stable.

**Context:** tdd BOOTSTRAP.md. User: "let the agent chose according to the claude code docs". Pasted `.claude/agents/` as the answer; same path leaked into SKILL.md + README.md. Future agent never invokes `claude-docs`.
