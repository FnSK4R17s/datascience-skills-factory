# Skill Design Philosophy for Multica

How to write skills that agents actually follow. This isn't about the SKILL.md format — it's about what goes inside them and why agents ignore some skills and obey others.

---

## The Core Problem

Agents have training data, codebase context, and your skill — in that priority order. When your skill says "do X" but the codebase or training suggests "do Y," the agent does Y. Skills compete for attention against everything else the agent knows.

**A skill that describes what to do gets ignored. A skill that provides the exact output to copy gets followed.**

---

## Rule 1: Templates Over Instructions

Bad:
```
Use the dataclass pattern for pipeline state. Don't use LangGraph for linear pipelines.
```

Good:
```python
# MANDATORY — copy and adapt this exact template:
@dataclass
class <AgentName>PipelineState:
    engagement_id: str
    model_name: str = "gpt-4.1-mini"
    raw_data: dict[str, Any] | None = None
    context: dict[str, Any] | None = None
    rag_context: str = ""
    rag_sources: list[SourceReference] = field(default_factory=list)
    result: <OutputModel> | None = None
    markdown: str = ""
    artifact_id: str | None = None
```

**Why:** The agent sees the template, copies it, and adapts it. It doesn't need to make a judgment call about what "the dataclass pattern" means. The template IS the instruction.

**How to get templates:** Extract them from your production codebase. Don't write idealized versions — copy working code and generalize the names.

---

## Rule 2: Ban Patterns By Name

Bad:
```
Avoid unnecessarily complex frameworks.
```

Good:
```
## BANNED — Never use these in new pipeline code:
- `from langgraph.graph import StateGraph` — only allowed in pipeline/agent/service.py
- `class MyState(TypedDict)` — use @dataclass instead
- `if state.get("error"): return {}` — use try/except at the top level
- `add_node()`, `add_edge()`, `compile()` — LangGraph graph construction

If you find yourself importing langgraph, STOP. Use the sequential async template above.
```

**Why:** "Avoid complex frameworks" is subjective. The agent can rationalize that LangGraph isn't complex, it's "standard." But "never import `StateGraph`" is binary — the agent either does or doesn't.

---

## Rule 3: Pre-Flight Checks Are Mandatory

Bad:
```
Consider checking if this already exists before building it.
```

Good:
```
## BEFORE YOU START — Run these checks. Do not skip them.

1. Run `ls pipeline/` — list all existing modules
2. Run `multica issue search "<agent name>"` — check for existing issues
3. If the module already exists, DO NOT create a new one. Post a comment saying
   "Module already exists at pipeline/<name>/" and stop.
```

**Why:** "Consider checking" is optional. The agent will skip it to get to the interesting work faster. Making it a numbered mandatory step with a specific command to run and a specific action if the check fails turns it into a gate.

---

## Rule 4: One Skill, One Shape of Output

A skill should produce a predictable output shape. If someone reads 10 outputs from agents using your skill, they should look structurally identical — same sections, same order, same formatting.

**Define the exact output format in the skill:**

```markdown
## Output Format — Your comment on each issue MUST follow this structure:

### PRD Summary
<What the PRD says — cite sections>

### Pipeline Code
<Full code following the template above>

### Agent Settings
| Setting | Default | Range | What It Controls |
|---------|---------|-------|-----------------|
| ... | ... | ... | ... |

### Open Questions for SME
<Numbered list>
```

**Why:** Without a defined output shape, each agent run produces a different structure. The next agent in the chain can't reliably parse it. The human reviewing it has to re-orient every time.

---

## Rule 5: Reference Real Code, Not Idealized Code

Bad:
```python
# Template: fetch engagement data
async def fetch_data(engagement_id: str):
    # Call your API here
    pass
```

Good:
```python
# From pipeline/estimate/data_assembler.py (production code):
from pipeline.ssp_client import ssp_client

async def fetch_engagement(engagement_id: str) -> dict[str, Any]:
    async with ssp_client() as client:
        resp = await client.get(f"/engagements/{engagement_id}")
        if resp.status_code == 404:
            resp = await client.get(f"/deals/{engagement_id}")
        resp.raise_for_status()
        return resp.json()
```

**Why:** The idealized version leaves every decision to the agent (which client? what URL? error handling?). The production version answers all those questions. The agent copies it and changes the parts that differ.

**Cite the source file.** When the agent can see that the template came from `pipeline/estimate/data_assembler.py`, it treats it as authoritative. An anonymous template gets less respect.

---

## Rule 6: Skills Compound — Layer Them

Don't put everything in one mega-skill. Layer them:

- **Platform skill** (multica) — how to use the CLI, create issues, manage agents
- **Domain skill** (scaffolder) — codebase patterns, templates, directory structure
- **Search skill** (qmd-search) — how to query the knowledge base
- **Process skill** (playbook) — orchestration patterns, chaining, batch ops

An agent with all four skills can: scaffold a pipeline (scaffolder) → search the PRD for context (qmd) → create sub-issues (multica) → chain to the next agent (playbook).

**Attach the minimum set of skills needed.** An agent that creates presentations doesn't need the scaffolder skill. An agent that searches the wiki doesn't need the playbook. More skills = more context = more competition for the agent's attention.

---

## Rule 7: Write for the Agent That Will Ignore You

Assume the agent:
- Skips anything marked "optional" or "consider"
- Falls back to training data when your instructions are vague
- Copies the nearest pattern it can find, even if that pattern is wrong
- Doesn't read the full skill — it skims for the relevant section

**Design for this agent:**
- Mark mandatory steps with "MANDATORY," "REQUIRED," or "DO NOT SKIP"
- Put the most important template first — agents weight earlier content higher
- Use section headers that match the task ("## Pipeline State Template" not "## Architecture Considerations")
- Keep the skill under 40K chars — beyond that, later sections get less attention

---

## Rule 8: Version Your Skill Content

When you update a skill, running tasks don't pick up the change. Only new tasks see the new version. This means:

- **Update the skill BEFORE triggering the batch** — not while agents are already running
- **If you update mid-run**, you need to archive the agent (cancels running tasks), then re-trigger
- **Document what changed** — add a comment on the relevant issues saying "Skill updated: added X, changed Y"

**Tag your skill with a version comment at the top:**
```markdown
<!-- v3 — 2026-05-07: Added multi-capability template, banned LangGraph -->
```

This helps you track which version agents were using when they produced their output.

---

## Rule 9: The Skill Is the Contract

When Agent A hands off to Agent B via @-mention, Agent B reads the issue thread. But the issue thread is noisy — it has multiple comments, multiple agent outputs, human replies. Agent B needs to know what to look for.

**The skill defines what the previous agent's output looks like and what to do with it:**

```
## When You're Triggered

You get @-mentioned on an issue where the Consultant has already posted a scaffold.
The scaffold comment contains:
- PRD Summary (under ### PRD Summary)
- Pipeline Code (under ### Pipeline Code)
- Agent Settings (under ### Agent Settings)
- Open Questions (under ### Open Questions for SME)

Read the LAST comment from an agent with author_type "agent" that starts with
"## Scaffold:" — that's the one you need.
```

**Why:** Without this, Agent B parses the whole thread and picks whatever seems relevant. With this, it knows exactly which comment to read and what sections to extract.

---

## Checklist: Before Publishing a Skill

- [ ] Does every instruction have a concrete template or example?
- [ ] Are banned patterns listed by exact import/function name?
- [ ] Are pre-flight checks numbered and mandatory?
- [ ] Is the output format defined with exact section headers?
- [ ] Are code templates extracted from production, not idealized?
- [ ] Is the skill under 40K chars?
- [ ] Have you tested it on one issue before running a batch?
- [ ] Does the skill tell the agent what the previous agent's output looks like (if chained)?
