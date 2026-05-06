# Multica Playbook — Agent Orchestration Patterns

Practical patterns for orchestrating multi-agent workflows in Multica. These are battle-tested from real production use — scaffolding 12 pipeline agents across a team, running SME review cycles, and automating PR creation.

For CLI commands and platform reference, see [SKILL.md](SKILL.md) and [INDEX.md](INDEX.md).

---

## Core Principle

The power of Multica is custom automation: create an agent for a task, attach the right skills, point it at a batch of issues, trigger it. Agents are disposable. **Skills** (encoded judgment) and **issues** (accumulated context) are what persist.

---

## Pattern 1: Anchor Ticket + Fan-Out

**When to use:** You have one big task that decomposes into many parallel subtasks.

**How it works:**
1. Create a parent issue (the "anchor ticket") describing the full scope
2. Assign an orchestrator agent to the anchor ticket
3. The agent reads the anchor, creates sub-issues (one per unit of work), assigns them
4. Sub-issues execute in parallel up to the daemon's concurrency limit

```bash
# Create the anchor
multica issue create --title "Scaffold all PRD agents" --priority high --output json

# Create an autopilot to trigger it
multica autopilot create --title "Scaffold sweep" --agent Consultant \
  --mode create_issue --issue-title-template "Scaffold sweep — {{date}}"

# Fire it
multica autopilot trigger <autopilot-id>
```

**Key detail:** The agent on the anchor ticket uses `multica issue create --parent <anchor-id>` to create sub-issues, then `multica issue assign <id> --to <agent>` to assign them. All sub-issues inherit the anchor as their parent — you can track everything from one place.

**Concurrency:** Default is 6 per agent, 20 per daemon. If you create 12 sub-issues assigned to the same agent, 6 run immediately and 6 queue. Adjust with `--max-concurrent-tasks` on the agent.

---

## Pattern 2: Agent Chaining via @-Mentions

**When to use:** Agent B needs Agent A's output before it can start.

**How it works:** Agent A's instructions include "when done, @-mention Agent B." The @-mention creates a new task for Agent B on the same issue. Agent B reads the issue thread (which now contains Agent A's output) and continues.

```
Agent A finishes work → posts output as comment → posts "@Agent-B do X"
  → Multica creates a task for Agent B on this issue
  → Agent B reads the full thread (including A's output) and executes
```

**In the agent's system prompt:**
```
After posting the scaffold, @-mention Showcase on the sub-issue:
  @Showcase Build the preview page for this agent.
```

**Critical rule:** Never @-mention two agents simultaneously if one depends on the other's output. The mentions fire as independent tasks with no ordering guarantee.

**Anti-loop rule:** Add to instructions: "Never @-mention the agent that triggered you on the same issue." This prevents A → B → A → B infinite loops.

---

## Pattern 3: Archive/Restore for Concurrency Control

**When to use:** You need to pause one agent's work to free daemon slots for another, or you need to cancel all of an agent's tasks quickly.

**How it works:**
- `multica agent archive <id>` — immediately cancels ALL running and queued tasks for that agent
- `multica agent restore <id>` — brings the agent back online but does NOT re-queue cancelled tasks
- To re-trigger, post new @-mentions on the relevant issues

```bash
# Stop Atlas — frees 6 daemon slots
multica agent archive <atlas-id>

# Wait for Showcase to finish, then bring Atlas back
multica agent restore <atlas-id>

# Re-trigger Atlas on all issues (cancelled tasks don't come back)
for issue in AIN-272 AIN-273 AIN-274; do
  multica issue comment add "$issue" --content "@Atlas commit and push"
done
```

**Use case:** Agent A and Agent B are both maxing out concurrency and competing for slots, but Agent A's work is higher priority. Archive Agent B, let Agent A finish, restore Agent B.

---

## Pattern 4: Every Agent Commits Its Own Code

**When to use:** You want to eliminate handovers between "the agent that writes code" and "the agent that commits code."

**Why:** Having a separate agent just for git operations (checkout, commit, push, PR) adds a handover that requires sequencing. If the writing agent also commits, you cut the pipeline in half.

**In the agent's instructions:**
```
After writing the code:
1. git checkout -b <branch-name>
2. git add the relevant files
3. git commit with a descriptive message
4. git push -u origin <branch-name>
5. gh pr create --title "..." --body "..."
6. Post the PR link as a comment on the issue
```

**When NOT to do this:** When you want a review step between writing and committing, or when the agent doesn't have filesystem access to the repo.

---

## Pattern 5: Batch Triggering via Shell Loop

**When to use:** You need to trigger the same agent on many issues at once.

```bash
for issue in AIN-272 AIN-273 AIN-274 AIN-275 AIN-276; do
  multica issue comment add "$issue" \
    --content "@Agent-Name Do the thing. Context is in the thread above."
done
```

**Tip:** The daemon picks up tasks as fast as they're created. If you're triggering 12 issues but the agent's concurrency is 6, the first 6 start immediately and the rest queue. No manual pacing needed.

**Tip:** Use `--output json` on `issue create` to capture IDs for the loop:
```bash
multica issue search "Scaffold" --output json | \
  python3 -c "import sys,json; [print(i['identifier']) for i in json.load(sys.stdin)]"
```

---

## Pattern 6: Skill-Driven Development

**When to use:** Always. Skills are the most important asset in the system.

**The lesson:** Agents follow concrete templates. They ignore vague instructions. If your skill says "don't use LangGraph" but doesn't provide an alternative template, the agent will use LangGraph anyway because it's a familiar pattern.

**Rules for writing skills:**
1. **Templates over instructions** — provide copy-pasteable code, not descriptions of what code should look like
2. **Anti-patterns are explicit** — list banned imports, banned patterns, with the exact strings to avoid
3. **Pre-flight checks are mandatory** — "before writing code, run `ls pipeline/` to check what exists"
4. **Examples come from the real codebase** — extract working patterns from production code, don't write idealized versions

**Bad skill:**
```
Use the dataclass pattern for pipeline state. Don't use LangGraph.
```

**Good skill:**
```python
# MANDATORY pattern — copy and adapt:
@dataclass
class <AgentName>PipelineState:
    engagement_id: str
    model_name: str = "gpt-4.1-mini"
    raw_data: dict[str, Any] | None = None
    # ... (full template with all fields)

# BANNED — do not use:
# from langgraph.graph import StateGraph  ← NEVER for linear pipelines
# class MyState(TypedDict):              ← use @dataclass instead
```

---

## Pattern 7: Multi-Capability Agents

**When to use:** A single PRD agent has multiple features (e.g., SPARC does 9-box, engagement brief, risk flagging, scope scoring — 13 capabilities total).

**How it works:**
- Each capability is a separate pipeline with its own API endpoint
- The preview page has a sidebar listing all capabilities with status badges (built/planned)
- Built capabilities are interactive; planned ones show the PRD spec
- A capability registry in the preview server maps IDs to pipeline functions

```python
CAPABILITIES = [
    {"id": "nine_box", "name": "9-Box Summary", "status": "built"},
    {"id": "engagement_brief", "name": "Engagement Brief", "status": "built"},
    {"id": "risk_flagging", "name": "Early Risk Flagging", "status": "planned"},
]
```

**Key:** Post the full capability breakdown on the issue BEFORE the agent starts work. The agent needs to know exactly how many endpoints to create and which ones have existing code to wire up.

---

## Pattern 8: Autopilot as Batch Trigger

**When to use:** You want a repeatable way to kick off a workflow — either on schedule or on demand.

**How it works:** An autopilot creates a sweep issue and assigns it to an agent. The agent reads a parent ticket, finds unprocessed children, and works through them.

```bash
multica autopilot create \
  --title "Scaffold sweep" \
  --agent Consultant \
  --mode create_issue \
  --issue-title-template "Scaffold sweep — {{date}}" \
  --description "Scan AIN-270 for agents not yet scaffolded. Create sub-issues for missing ones."

# Manual trigger
multica autopilot trigger <id>

# Or add a cron for automatic runs
# (via the UI — cron triggers not yet in CLI)
```

**The autopilot doesn't do the work** — it creates an issue, assigns it to the agent, and the agent does the work. Think of it as a "start button" that can be pressed manually or on a timer.

---

## Pattern 9: Delayed Execution

**When to use:** Agent B should run after Agent A, but you don't want to sit around waiting.

**How it works:** Use a background shell command with `sleep` to trigger Agent B after a delay.

```bash
# In the background: wait 1 hour, then trigger Showcase
sleep 3600 && for issue in AIN-272 AIN-273 AIN-274; do
  multica issue comment add "$issue" --content "@Showcase build the preview page"
done
```

**Better approach:** Check if Agent A is actually done before triggering:

```bash
sleep 3600 && \
RUNNING=$(multica agent tasks <agent-a-id> --output json | \
  python3 -c "import sys,json; print(len([t for t in json.load(sys.stdin) if t['status']=='running']))") && \
if [ "$RUNNING" = "0" ]; then
  # Agent A is done, trigger Agent B
  for issue in AIN-272 AIN-273; do
    multica issue comment add "$issue" --content "@Agent-B your turn"
  done
fi
```

**Note:** This is a workaround. Multica doesn't have native "run after" triggers yet. The @-mention chaining pattern (Pattern 2) is usually better — the agent triggers the next one as its last action.

---

## Anti-Patterns

### Don't: @-mention two dependent agents simultaneously
Both fire at once with no ordering. Agent B will read the issue before Agent A has posted its output.

### Don't: Write vague skill instructions
"Use good patterns" means nothing. Provide the exact code template. Agents fall back to training data when instructions are ambiguous.

### Don't: Scaffold without checking what exists
Always include a pre-flight step: `ls pipeline/` or `multica issue search "X"` to check for existing implementations. Duplicating working code wastes cycles and creates confusion.

### Don't: Build everything regardless of priority
Gate your automation: "Only scaffold agents marked Confirmed MVP." Without this, the agent will happily build all 12 agents including the Phase 3 ones nobody needs yet.

### Don't: Rely on a single long-running agent for everything
Split the work across specialized agents. One agent scaffolding + committing + building preview pages + creating PRs will hit context limits. Let each agent do one thing well.

---

## Quick Reference: Common Workflows

### Scaffold a new pipeline agent
```
1. Create anchor ticket with scope
2. Trigger Consultant autopilot → fan-out sub-issues
3. Consultant scaffolds + @Showcase
4. Showcase builds preview page
5. Agent commits + opens PR
```

### Run an SME review cycle
```
1. Generate output via preview page (pick real engagement)
2. Export one-pager → send to SME
3. SME replies with feedback on the issue
4. @Agent to iterate based on feedback
```

### Emergency: stop all work for an agent
```bash
multica agent archive <id>   # cancels everything immediately
multica agent restore <id>   # brings it back without re-queuing
```

### Check what's running across all agents
```bash
multica agent list --output json | python3 -c "
import sys, json, subprocess
for a in json.load(sys.stdin):
    r = subprocess.run(['multica','agent','tasks',a['id'],'--output','json'], capture_output=True, text=True)
    tasks = json.loads(r.stdout) if r.stdout else []
    running = len([t for t in tasks if t['status']=='running'])
    queued = len([t for t in tasks if t['status']=='queued'])
    if running or queued:
        print(f\"  {a['name']:15s}  running={running}  queued={queued}\")
"
```
