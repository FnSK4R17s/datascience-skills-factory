---
name: plan-feature
description: >
  Plan a new feature for an existing codebase by walking the user through four
  stages — Research, Requirements, Deep Research, Backlog Item — and producing
  a single agent-ready backlog document in karpathy-style abstraction. Each
  invocation creates or resumes a feature plan under `plan/<slug>/`. The final
  backlog item is written in a form that can be handed to an implementing LLM
  agent. Use when the user says "plan a feature", "scope this feature",
  "write a backlog item", "draft a feature spec", or invokes /plan-feature.
  For first-time setup in a repo, see BOOTSTRAP.md.
---

# plan-feature Skill

Interactive, stage-gated feature planner for existing codebases. Produces one
agent-ready backlog item per feature.

## When to use

Trigger when the user wants to scope a feature-level change in the current
repo and end up with a backlog item a coding agent can execute. Not for
whole-product PRDs (use `prd-karpathy-style` for that). Not for bug reports
(use `bugfix`).

## Prerequisites

The repo must have a `plan/` folder containing `PLAN.md` and `.planconfig`.
If missing, stop and point the user at `BOOTSTRAP.md`. Do not auto-bootstrap —
bootstrap is a one-time deliberate setup.

## On every invocation

1. **Verify setup.** Read `plan/PLAN.md` and `plan/.planconfig`. If either is
   missing, tell the user to run BOOTSTRAP.md first.
2. **Determine intent.** Ask:
   - New feature? → gather title, derive kebab-case slug, confirm with user.
   - Resume existing? → list features from `PLAN.md` with their current stage.
3. **New feature setup:**
   - `mkdir plan/<slug>`
   - Copy templates `01-research.md`, `02-requirements.md`,
     `03-deep-research.md`, `04-backlog-item.md` into `plan/<slug>/`.
   - Append a new row to the feature table in `plan/PLAN.md` with all stages
     set to `⏳` and status set to `draft`.
4. **Resume existing feature:** find the first non-`✅` stage cell and start
   there.
5. **Run the stage** (see stage prompts below).
6. **After stage completes:** write the stage file, mark the cell `✅` in
   `PLAN.md`, and ask the user whether to proceed to the next stage now or
   stop.

## Config

`plan/.planconfig` is YAML. Honor every flag. Key flags:

- `search.qmd_stage1` (bool) — enable qmd in Research stage.
- `search.qmd_stage3` (bool) — enable qmd in Deep Research stage.
- `search.qmd_collection` (string) — collection name, or `auto` to detect.
- `search.web_fetch_stage3` (bool) — allow WebFetch in Deep Research.
- `search.codebase_search` (bool) — enable Grep/Glob/Read codebase scans.
- `format.slug_case` — default `kebab`.
- `format.status` — `freeform` (default) or `enum`.

If a flag is missing, default to `true` for search flags and `kebab`/`freeform`
for format flags.

## Slug rules

- Kebab-case, lowercase, ASCII, no spaces.
- If user supplies only a title ("User-facing SSO login"), derive
  `user-facing-sso-login` and confirm before creating the directory.
- Reject slugs that already exist in `plan/` — ask whether to resume or pick a
  new slug.

---

## Stage 1 — Research

**Goal:** map what already exists in the codebase that this feature will touch
or depend on. Output is factual, not prescriptive.

**Inputs:** feature title, user's one-liner description.

**Steps:**

1. Ask the user for a one-line description of the feature if not already given.
2. Codebase scan (if `codebase_search: true`):
   - Use Grep/Glob to locate modules, configs, and tests related to the
     feature's surface area.
   - Read the top 3–5 most relevant files in full.
   - For broad exploration consider spawning an `Explore` subagent.
3. qmd scan (if `qmd_stage1: true`):
   - Run `mcp__qmd__query` against the configured collection with a lexical
     and a vector sub-query.
   - Keep top 5 results; note qmd results can be broad — filter to what is
     clearly relevant before citing.
4. Fill the `01-research.md` template. Do not invent findings.
5. Update PLAN.md row: Research cell → `✅`.

**Do not:** propose a design, list requirements, or write code. This stage is
observation only.

---

## Stage 2 — Requirements

**Goal:** turn the research into a concrete, user-facing contract. This stage
is interactive.

**Steps:**

1. Read `01-research.md` for context.
2. Use AskUserQuestion to cover, in order:
   - Who is the user / caller?
   - What is the minimum shippable behavior (v1)?
   - What is explicitly out of scope?
   - Acceptance criteria — how does the user know it works?
   - Non-functional constraints (perf, security, compat).
3. Record every user answer verbatim in `02-requirements.md` under the
   matching section. Do not paraphrase away their wording.
4. Flag open questions at the bottom — these drive Stage 3.
5. Update PLAN.md row: Requirements cell → `✅`.

**Do not:** pick a technical solution. That happens in Stage 4.

---

## Stage 3 — Deep Research

**Goal:** resolve the open questions from Stage 2 and pressure-test the
approach.

**Steps:**

1. Read `01-research.md` and `02-requirements.md`. Start from the
   "Open questions" list.
2. For each open question pick the minimum research method:
   - Codebase-only for "how does X currently behave" questions.
   - qmd (if `qmd_stage3: true`) for "does our docs/wiki mention Y".
   - WebFetch (if `web_fetch_stage3: true`) for library docs, RFCs, or
     external APIs.
3. For each question write a sub-section in `03-deep-research.md`:
   question, method, finding, implication for the design.
4. Surface any new risks discovered — add a Risks list at the bottom.
5. Update PLAN.md row: Deep Research cell → `✅`.

**Do not:** expand scope. If research reveals the feature is much bigger than
thought, stop and tell the user — they decide whether to split.

---

## Stage 4 — Backlog Item

**Goal:** produce the single handoff document in karpathy-style abstraction,
scoped to one feature in an existing codebase. The document must be concrete
enough to be actionable, abstract enough to not over-specify implementation,
and opinionated enough to be useful.

**Steps:**

1. Read all three prior stage files.
2. Fill `04-backlog-item.md` following the template exactly — every section
   is required. Section order is fixed. Do not invent new top-level sections.
3. Update PLAN.md row: Backlog cell → `✅`, Status → `v1 ready`.
4. Tell the user the backlog item is at `plan/<slug>/04-backlog-item.md` and
   can be pasted into an implementing agent's context along with the three
   stage files.

### Style rules (enforce these strictly)

1. **Quotable one-liner** — the document opens with a `>` blockquote that
   captures the entire feature in one sentence.
2. **"This is an idea file" paragraph** — immediately after the quote, state
   the document is designed to be shared with an implementing agent and
   built out collaboratively.
3. **Status-quo-vs-new framing** — the "What changes" section explains what
   the system does today, why that's insufficient, and how the new behavior
   is different. Use concrete file paths and module names. The rhetorical
   move is "Today `X` does `Y`. After this, `X` does `Z` because `W`."
4. **Bold the key insight** — every major section has one bolded sentence
   that captures its central point. This is the sentence a skimmer would
   highlight.
5. **Touchpoints as named layers** — the "Touchpoints" section lists
   affected modules as bold-named layers, one paragraph each. Describe
   *what* each layer does in this feature and *why*, not *how*.
6. **Workflow as numbered steps** — the "Workflow" section walks through
   the 1–3 user-triggered flows through the new behavior. Keep each step
   high-level — one sentence.
7. **One concrete example** — the "Example" section picks a single specific
   instance (one user, one input, one path) and walks it through end to
   end. Include sample data, sample request, sample output. This grounds
   the abstraction.
8. **Stack table** — a markdown table with Component | Technology | Status
   columns. Status is one of: `Built` (already in repo), `Available`
   (library installed, not yet used for this feature), `To build` (new).
9. **"What makes this hard"** — 2–4 genuine challenges from Stage 3. Each
   2–3 sentences: why it is hard, and a mitigation sketch. Be honest. Do
   not hand-wave.
10. **"Why this works"** — closing argument. One paragraph connecting the
    feature's shape to a deeper observation about the existing codebase or
    the user's workflow. Reference prior art in the repo if relevant.
11. **"Note" paragraph** — the document is intentionally abstract,
    implementation details depend on the state of the codebase at
    implementation time, and the right way to use the document is to share
    it with an implementing agent.

### Tone and voice

- Second person ("you") or neutral third person. **Never** first person
  plural ("we").
- Be opinionated. State what is better and why. No hedging — drop
  "could potentially", "might be useful", "one option is".
- Concrete over abstract. "The `/auth/login` handler in `auth.py:42`" not
  "the authentication layer". "A user hits the bulk-import button with a
  3-column CSV" not "a user performs an import action".
- Short paragraphs — 2–4 sentences. Readers skim.
- No bullet points inside prose sections. Bullets only inside Touchpoints,
  Workflow, Stack, What makes this hard, and Acceptance criteria.
- No marketing language. Drop "revolutionary", "game-changing",
  "best-in-class", "seamless".
- Analogies are encouraged. "The scheduler is the dispatcher; the queue is
  the mailbox; the worker is the courier."

### Do not include

- No naming or branding discussion
- No pricing, business model, or ROI framing
- No timeline, roadmap, or milestone dates
- No user personas or market analysis
- No wireframes or UI mockup descriptions — describe behavior, not pixels
- No full restatement of Stage 1–3 content — reference the files instead

---

## Maintaining `plan/PLAN.md`

`PLAN.md` is the index for the whole `plan/` folder. Every cell in the
feature table is a link — readers click through to the feature folder or
a specific stage file.

**Cell format:**

- **Feature column:** `[<slug>](<slug>/)` — links to the feature folder.
- **Stage cells:** `[<glyph>](<slug>/0N-stage-name.md)` — the status glyph
  is the link text, the href is the stage file. Glyphs: `⏳` not started,
  `🚧` in progress, `✅` done.
- **Status column:** freeform text, **not a link**. Typical values:
  `draft`, `v1 ready`, `v1 done`, `v2 done`, `archived`. If `.planconfig`
  sets `format.status: enum`, restrict to that set.

When a feature is first created (Stage 1 setup), write a row with the
feature link and four stage links, each using `⏳` as link text, because
all four template files exist from the start. Update the glyph in place on
every stage transition — never rewrite the href. After any edit, move the
feature's row to the top to preserve most-recently-touched order.

**Example row:**

```markdown
| [user-sso](user-sso/) | [✅](user-sso/01-research.md) | [🚧](user-sso/02-requirements.md) | [⏳](user-sso/03-deep-research.md) | [⏳](user-sso/04-backlog-item.md) | draft |
```

## Files this skill owns

- `SKILL.md` — this file.
- `BOOTSTRAP.md` — one-time setup per repo.
- `templates/PLAN.md` — global index.
- `templates/.planconfig` — config defaults.
- `templates/01-research.md` through `templates/04-backlog-item.md` — stage
  scaffolds copied into each new feature directory.
