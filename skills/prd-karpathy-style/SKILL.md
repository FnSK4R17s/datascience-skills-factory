---
name: prd-karpathy-style
description: "Create product requirement documents (PRDs) in the Karpathy LLM Wiki style — abstract, opinionated idea documents designed to be handed to an LLM agent for implementation. Use this skill whenever the user asks for a PRD, product spec, product requirement document, idea document, architecture doc, or design doc. Also trigger when the user says 'write a PRD', 'create a spec', 'document this product idea', 'write up this concept', or wants to capture a product vision as a structured document. Works for any domain — ed-tech, SaaS, developer tools, consumer apps, hardware, research tools, etc."
---

# Karpathy-Style PRD Creator

## What this produces

A single markdown file (.md) that communicates a product idea at the right level of abstraction — concrete enough to be actionable, abstract enough to not over-specify implementation. The document is designed to be copy-pasted into an LLM agent's context so the agent can build out the specifics.

## Style principles

The Karpathy PRD style has specific characteristics. Follow all of them:

1. **Open with a quotable one-liner** — a `>` blockquote that captures the entire idea in one sentence.
2. **"This is an idea file" disclaimer** — immediately after the quote, state that this document is meant to be shared with an LLM agent and built out collaboratively.
3. **"The core idea" section** — explain what exists today (the status quo), why it's insufficient, and how this product is different. Use concrete comparisons. Name existing products. The key rhetorical move: "Most X works like Y. This is different because Z."
4. **Bold the key insight** — every section should have one bolded sentence that captures its central point. This is the sentence someone would highlight if they were skimming.
5. **Architecture section** — describe the system as numbered layers or components. Each layer gets a bold name and a one-paragraph description. Don't over-specify APIs or schemas — describe *what* each layer does and *why*, not *how*.
6. **Operations section** — describe the 2-4 core workflows (e.g., Ingest, Query, Lint). Each workflow is a numbered sequence of steps. Keep steps high-level.
7. **Concrete example or proof of concept** — pick ONE specific instance of the product in action and walk through it in detail. Include sample content (scripts, data, UI flows). This grounds the abstract architecture in reality.
8. **Stack table** — a markdown table with Component | Technology | Status columns. Be specific about tools and libraries. Status is one of: Built, Available, To build.
9. **"What makes this hard" section** — numbered list of genuine challenges. Be honest. Don't hand-wave. Each challenge should be 2-3 sentences explaining why it's hard and what the mitigation might be.
10. **"Why this works" section** — the closing argument. Connect the product to a deeper insight about why this approach succeeds where others haven't. Reference prior art if relevant.
11. **"Note" section** — always end with a paragraph saying the document is intentionally abstract, implementation details depend on context, and the right way to use it is to share it with an LLM agent.

## Tone and voice

- Write in second person ("you") or neutral third person. Never first person plural ("we").
- Be opinionated. State what's better and why. Don't hedge with "could potentially" or "might be useful."
- Use concrete examples over abstract descriptions. "Newton sitting under a tree" not "educational narrative content."
- Short paragraphs. Most paragraphs are 2-4 sentences.
- No bullet points in prose sections — use them only in the architecture, operations, and challenges sections.
- No marketing language. No "revolutionary," "game-changing," "cutting-edge." Just describe what it does and why that matters.
- Analogies are encouraged. "Obsidian is the IDE; the LLM is the programmer; the wiki is the codebase."

## Structure template

```markdown
# [Product Name]

> [One-sentence description of the entire idea.]

[This is an idea file paragraph — designed to be shared with an LLM agent.]

## The core idea

[Status quo. Why it's broken. How this is different. Bold the key insight.]

## Architecture

[Numbered or named layers/components. Bold names. One paragraph each.]

## [Core concept that needs its own section]

[If the product has a novel model or mechanism (e.g., a difficulty model, a pricing model, a scoring system), give it its own section with concrete examples at different levels.]

## Operations

[2-4 core workflows. Numbered steps. High-level.]

## [Proof of concept / concrete example]

[One specific instance walked through in detail. Include sample content.]

## Stack

| Component | Technology | Status |
|-----------|-----------|--------|
| ... | ... | ... |

## What makes this hard

[Numbered challenges. Honest. 2-3 sentences each.]

## Why this works

[Closing argument. Deeper insight. Prior art references.]

## Note

[Intentionally abstract. Implementation depends on context. Share with your LLM agent.]
```

## Process

1. **Gather context** — ask the user about the product idea. What does it do? Who is it for? What exists today? What's the key differentiator? What's the tech stack? Don't start writing until you have enough to fill the architecture and stack sections.

2. **Draft the PRD** — write the full document following the structure template and style principles. Save as a .md file.

3. **Iterate** — the user will likely want to add, remove, or adjust sections. Make targeted edits. Don't rewrite the whole document unless asked.

## What NOT to include

- No naming/branding sections (unless explicitly requested)
- No pricing or business model sections (unless explicitly requested)
- No timeline or roadmap — the document is about *what*, not *when*
- No user personas or market analysis — this is a technical idea doc, not a business plan
- No wireframes or UI mockups — describe behavior, not layout

## Output

Save the PRD as `[PRODUCT_NAME]_PRD.md` in the outputs directory. Use SCREAMING_SNAKE_CASE for the filename. Present it to the user with `present_files`.
