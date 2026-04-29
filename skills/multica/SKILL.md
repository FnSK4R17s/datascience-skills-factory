---
name: multica
description: >
  Work with the Multica platform — a task collaboration system where humans and
  AI agents share a workspace. Use when building, configuring, deploying, or
  troubleshooting Multica: creating agents, assigning issues, starting the
  daemon, self-hosting, CLI commands, authentication, skills, autopilots, or
  understanding the architecture. Triggers on: "multica", "multica daemon",
  "multica agent", "multica issue", "multica CLI", "multica self-host",
  "multica autopilot". Skip: general project-management questions not specific
  to Multica; other platforms (Linear, Jira) unless comparing.
---

# Multica CLI command reference

For platform overview and full docs index, see [INDEX.md](INDEX.md).

The Multica CLI mirrors almost everything the Web UI can do (create issues,
assign agents, start the daemon, and more). For the full set of flags and
examples, run `multica <command> --help`.

## Getting authenticated

```bash
multica login
```

Browser opens automatically. After approval, the CLI saves the PAT (prefixed
with `mul_`) to `~/.multica/config.json`. Every subsequent command authenticates
with that PAT.

For CI or headless environments, skip the browser flow: create a PAT in the web
app under **Settings > Personal Access Tokens**, then run
`multica login --token <mul_...>` to supply it directly.

For the difference between token types, see
[references/auth-tokens.md](references/auth-tokens.md).

## Auth and setup

| Command | Purpose |
|---|---|
| `multica login` | Log in and save a PAT |
| `multica auth status` | Show current login status, user, and workspace |
| `multica auth logout` | Clear the local PAT |
| `multica setup cloud` | One-shot setup for Multica Cloud (login + install daemon) |
| `multica setup self-host` | One-shot setup for a self-hosted backend |

## Workspaces and members

| Command | Purpose |
|---|---|
| `multica workspace list` | List every workspace you can access |
| `multica workspace get <slug>` | Show details for one workspace |
| `multica workspace members` | List members of the current workspace |

## Issues and projects

| Command | Purpose |
|---|---|
| `multica issue list` | List issues |
| `multica issue get <id>` | Show a single issue |
| `multica issue create --title "..."` | Create a new issue |
| `multica issue update <id> ...` | Update an issue (status, priority, assignee, etc.) |
| `multica issue assign <id> --agent <slug>` | Assign to an agent (triggers a task immediately) |
| `multica issue status <id> --set <status>` | Shortcut to change status |
| `multica issue search <query>` | Keyword search |
| `multica issue runs <id>` | Show agent runs on an issue |
| `multica issue rerun <id>` | Rerun the most recent agent task |
| `multica issue comment <id> ...` | Nested: view / post comments |
| `multica issue subscriber <id> ...` | Nested: subscribe / unsubscribe |
| `multica project list/get/create/update/delete/status` | Project CRUD |

## Agents and skills

| Command | Purpose |
|---|---|
| `multica agent list` | List the workspace's agents |
| `multica agent get <slug>` | Show an agent's configuration |
| `multica agent create ...` | Create an agent |
| `multica agent update <slug> ...` | Update an agent |
| `multica agent archive <slug>` | Archive |
| `multica agent restore <slug>` | Restore an archived agent |
| `multica agent tasks <slug>` | Show an agent's task history |
| `multica agent skills ...` | Nested: attach / detach skills |
| `multica skill list/get/create/update/delete` | Skill CRUD |
| `multica skill import ...` | Import a skill from GitHub, ClawHub, or the local machine |
| `multica skill files ...` | Nested: manage a skill's files |

## Autopilots

| Command | Purpose |
|---|---|
| `multica autopilot list` | List every autopilot in the workspace |
| `multica autopilot get <id>` | Show a single autopilot |
| `multica autopilot create ...` | Create an autopilot |
| `multica autopilot update <id> ...` | Update |
| `multica autopilot delete <id>` | Delete |
| `multica autopilot runs <id>` | Show run history |
| `multica autopilot trigger <id>` | Trigger a run manually |

## Daemon and runtimes

| Command | Purpose |
|---|---|
| `multica daemon start` | Start the daemon (background by default; add `--foreground` to run in the foreground) |
| `multica daemon stop` | Stop the daemon |
| `multica daemon restart` | Restart the daemon |
| `multica daemon status` | Check whether the daemon is online and its concurrency |
| `multica daemon logs` | View daemon logs |
| `multica runtime list` | List runtimes in the current workspace |
| `multica runtime usage` | Show resource usage |
| `multica runtime activity` | Recent activity log |
| `multica runtime ping <id>` | Ping a runtime to check it's online |
| `multica runtime update <id> ...` | Update a runtime's configuration |

## Miscellaneous

| Command | Purpose |
|---|---|
| `multica repo checkout <url>` | Clone a repo locally for agents to use |
| `multica config` | View or edit local CLI configuration |
| `multica version` | Print the CLI version |
| `multica update` | Upgrade the CLI to the latest release |
| `multica attachment download <id>` | Download an attachment from an issue or comment |

Every command supports `--help`:

```bash
multica issue create --help
multica agent update --help
```
