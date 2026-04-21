# ANTIPATTERNS

Real failures. Read before building.

---

## AP1 — Ship without end-to-end test

Unit smoke tests prove script parses. Don't prove system enforces what docs claim. Run full user flow in fresh /tmp project before claiming "works".

*Case: tdd skill. 50KB code, 2 unit tests passed. First real R-G-R cycle: GREEN didn't lock tests. Headline feature dead.*

## AP2 — Surface complexity ≠ value

50KB skill that breaks vs 9KB markdown that works → markdown wins. If competitor is 1/5 your size, justify the extra in one sentence or delete it.

*Case: tdd vs mattpocock/tdd. Theirs: 9.6KB markdown, no enforcement. Ours: hooks + AST + state machine. Ours broken.*

## AP3 — Hard gates without escape

Strict transition preconditions ("can't go A→B without X") trap users. Only escape becomes destructive reset or fake-the-precondition (reward-hack).

Fix: every gate gets an escape command documented next to it. Block writes (real anti-cheat); warn on phase claims (cheap to undo). Forward gates need backward commands that preserve context.

*Case: tdd R4. Test passed in RED → can't go GREEN, can't go back (R2 locked tests), only escape was reset (lose slice).*

## AP4 — Documented features that don't exist

Doc says "X is blocked". Code doesn't block X. Users trust doc. First slip = trust dead.

Fix: every "X is enforced" claim points to code line + test exercising both fire and no-fire. Can't point? Doc is fiction. Implement or delete claim.

*Case: tdd ANTIPATTERNS.md "AP12: hard retry budget MAX_RETRIES=3". No retry budget existed. Wishlist disguised as feature.*

## AP5 — Hardcoded skill-location math

`<skill>/../../agents/` assumes skill at `<root>/.claude/skills/<name>/`. Develop from checkout → files land in garbage location, silently.

Fix: print resolved target before any copy. Validate with realpath. Reject if not under expected ancestor.

*Case: tdd INSTALL.md step 2. Tested only at canonical path. Would have written agents to `/apps/datascience-skills-factory/agents/` from checkout.*

## AP6 — Inconsistent path keys in shared state

State file accumulates entries by path. One code path writes absolute, another writes relative. Same file, two keys. Lookups silently miss.

Fix: pick one form (relative-to-project-root). Normalize at every read AND every write. Add test that writes via one form, reads via other, asserts match.

*Case: tdd `state.test_counts` had both `tests/test_x.py` and `/tmp/proj/tests/test_x.py` for same file.*

## AP7 — "Works in unit tests" syndrome

Hand-crafted JSON payloads ≠ real Claude Code payloads. Real ones have missing keys, edge-case quoting, paths needing resolution. Script "works" in isolation, falls over in use.

Fix: unit test = sanity check. Validation = one cycle in fresh project with hooks wired through real settings.json, exercising user-facing slash commands.

*Case: tdd smoke tests across INSTALL/BOOTSTRAP/`/tdd-init` all hand-crafted JSON. None ran real R-G-R. Cascade bugs invisible until forced.*

## AP8 — Two install modes before one works

User-level + project-level + dispatcher + scope decision. Both modes share same bugs. Test surface doubled, time per mode halved. Ship two broken modes instead of one working one.

Fix: pick simpler scope (usually project). Ship that. Add second mode after first runs in N projects without surprise.

*Case: tdd went straight to dual-scope. Three rounds of refactoring before first end-to-end test. Test exposed bugs in both modes equally.*

## AP9 — Orchestration shell scripts hide work

`bootstrap.sh`/`install.sh`/`run_tests.sh` bundle 10–20 commands. Failure mid-flow = silent or compounded. Agent can't intervene. Re-run = error or worse.

Fix: markdown-driven install. One step = one observable op the agent verifies. Reserve shell only for hook dispatch.

*Case: tdd v1 had 5 wrapper scripts. User flagged liability. Ate multiple refactor rounds.*

## AP10 — Trigger keyword spam

Frontmatter description lists every keyword imaginable so skill always fires. Skill fires on tasks it can't do. Discovery system trust dies.

Fix: triggers = words user types when they specifically want THIS skill. Overlap with another skill? Narrow both. >6 keywords? Reaching.

## AP11 — Recommend untested tools

Doc says "compose with X" / "you could use Y". Never installed X or Y. Third-party AP4.

Fix: no recommend without end-to-end run in the same composition. No working example → delete the line.

*Case: tdd README "compose nizos/tdd-guard". Never installed. Cargo-cult name-drop.*

## AP12 — Touch user's global Claude config without permission

Writing `~/.claude/` (settings.json, skills/, agents/, commands/, hooks/, CLAUDE.md) without explicit in-message OK. Machine-wide config — breaks every project, not just this one. Backup-and-restore doesn't make it safe; backups fail.

Fix: testing → `/tmp/<scratch>/` or project-local `.claude/`. Need user-scope write? Stop, name the path, wait for yes. "I'll restore it" is not consent. "Just to check discovery" is the common excuse — user can install themselves.

*Case: tdd build session. Copied skill to `~/.claude/skills/tdd/`, agents to `~/.claude/agents/`, backed up + restored `~/.claude/settings.json`. User caught second instance, called it dangerous. Correctly.*

## AP13 — Hardcode live docs instead of deferring to lookup skill

Path / version / API gets snapshotted into static markdown. Doc has dedicated lookup skill (`claude-docs`, `vercel:*`, etc.) → ignore it, paste the answer. Snapshot rots; agent follows stale path forever.

Worse: user said "let the agent look it up". Hardcoding overrides their instruction and removes the lookup skill from the loop.

Fix: defer — "use the `claude-docs` skill to find X", not "X is at Y". Static docs are for stable contracts only (this skill's own behavior). External-project paths are never stable.

*Case: tdd BOOTSTRAP.md. User: "let the agent chose according to the claude code docs". I had fetched docs earlier in the session, pasted `.claude/agents/` as the answer. Same path leaked into SKILL.md + README.md. Future agent never invokes `claude-docs`.*

---

## Adding entries

New failure wastes real time → append entry same commit. Pattern / Why bites / Fix / Case. Name the skill. Don't sanitize.
