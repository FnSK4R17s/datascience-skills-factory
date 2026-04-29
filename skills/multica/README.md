<p align="center">
  <img src="logo.png" alt="Multica" height="88">
</p>

<h1 align="center">multica</h1>

<p align="center">
  <strong>Task collaboration where humans and AI agents share a workspace.</strong><br>
  <sub>Docs sourced from <a href="https://github.com/multica-ai/multica">multica-ai/multica</a></sub>
</p>

---

Teaches Claude to work with the Multica platform: creating and configuring
agents, assigning issues, running the daemon, self-hosting, CLI commands,
authentication, skills, autopilots, and the overall architecture. The 25
reference docs are copied as-is from the official Multica documentation.

## Install

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill multica
```

## File structure

```
multica/
├── SKILL.md                           # Entry point — CLI command reference
├── INDEX.md                           # Platform overview + routing table
├── README.md                          # This file
├── logo.png                           # Multica mark
└── references/
    ├── index.md                       # Welcome, where agents run
    ├── how-multica-works.md           # Three-component architecture
    ├── cloud-quickstart.md            # Sign up to first task in 5 min
    ├── self-host-quickstart.md        # Docker self-hosting
    ├── agents.md                      # What agents are
    ├── agents-create.md               # Creating and configuring agents
    ├── skills.md                      # Knowledge packs for agents
    ├── providers.md                   # 10 AI coding tools comparison
    ├── daemon-runtimes.md             # Daemon, runtimes, heartbeats
    ├── tasks.md                       # Task states, timeouts, retries
    ├── assigning-issues.md            # Assigning issues to agents
    ├── mentioning-agents.md           # @-mention trigger
    ├── chat.md                        # Private 1:1 agent chat
    ├── autopilots.md                  # Cron-scheduled agent runs
    ├── workspaces.md                  # Workspace creation, slugs
    ├── members-roles.md               # Owner / admin / member perms
    ├── issues.md                      # Issues, statuses, projects
    ├── comments.md                    # Threads, replies, reactions
    ├── inbox.md                       # Notifications, subscriptions
    ├── cli.md                         # CLI reference (mirrored in SKILL.md)
    ├── environment-variables.md       # Full env var reference
    ├── auth-setup.md                  # Sign-in, OAuth, 888888 trap
    ├── auth-tokens.md                 # JWT / PAT / daemon tokens
    ├── desktop-app.md                 # Native app, auto-daemon
    └── troubleshooting.md             # Top 7 issues + log locations
```

## When the skill fires

- User mentions Multica by name, or references its CLI (`multica daemon`,
  `multica issue`, `multica agent`).
- Building, configuring, deploying, or troubleshooting a Multica instance.
- Creating agents, attaching skills, setting up autopilots.
- Self-hosting Multica with Docker.

## When it should NOT fire

- General project-management questions not specific to Multica.
- Other platforms (Linear, Jira, GitHub Issues) unless comparing with Multica.

## Links

- Website: [multica.ai](https://multica.ai)
- Repository: [github.com/multica-ai/multica](https://github.com/multica-ai/multica)
