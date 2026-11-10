# parallel-work

A [Claude Code](https://claude.com/claude-code) skill for working through a GitHub backlog with parallel subagents. Each ticket gets a model and effort level that fit the job, and every agent keeps a progress log, so "status?" gets a real answer.

<!-- demo video: drag out/demo.mp4 into a PR or issue on GitHub and paste the user-attachments URL on its own line here -->

## Why

When Claude Code fans out work to subagents, each one inherits the main session's model and effort unless told otherwise. If your session runs Opus at high effort, so does the docs ticket, the same as the deadlock hunt. Long-running agents also don't report progress, so asking the main session how far they are gets a shrug.

## What it does

**Routes each ticket to a model and effort level.** The main session decides per ticket and shows you the plan before it dispatches:

```
#41 Document the env vars → haiku / low       (docs)
#42 Orders pagination     → sonnet / medium   (clear AC, existing pattern)
#43 Queue deadlock        → opus / high       (unknown root cause)
#44 Customers pagination  → same agent as #42 (reuses the paginator #42 creates)
```

| Ticket looks like | Model | Effort |
|---|---|---|
| Lookup, triage, docs, typo, rename | `haiku` | `low` |
| Clear acceptance criteria, follows an existing pattern | `sonnet` | `medium` |
| Clear spec, but tricky logic or many files | `sonnet` | `high` |
| Ambiguous spec, architecture, security, concurrency, unknown root cause | `opus` | `high` |
| Failed once at a lower tier | one tier up, at most `opus` / `high` | |

**Logs progress you can check.** Every subagent appends one line per milestone to `.parallel-work/agents/<ticket>.log`. Ask "status?" and the main session runs [`scripts/status.sh`](scripts/status.sh):

```
AGENT                  MODEL/EFFORT    STATE     QUIET   LAST UPDATE
41-env-docs            haiku/low       done      9m      16:31 | DONE | branch issue-41-env-docs
42-orders-pagination   sonnet/medium   running   2m      16:38 | verifying | 9 new tests pass
43-queue-deadlock      opus/high       STALE?    18m     16:22 | reproduce | hang in 3/10 runs
```

An agent with no log line for 15 minutes shows as `STALE?`. The main session then checks the agent's working copy for recent changes and tells you whether it's still working.

**Keeps you in charge of the expensive stuff.**

- `xhigh` and `max` are never used without your yes. When an `opus` / `high` run fails, Claude says what it learned and asks whether to escalate or whether you'd rather clarify the ticket.
- At most 5 subagents run at once, unless you say otherwise ("use 8 subagents", "as many as possible"). The rest wait in a queue and start as slots free up.
- Tickets that touch the same code, or build on each other, go to one agent in order, never to two agents in parallel.
- Agents push and open PRs only if you've asked for that (in the session or in `CLAUDE.md`). Otherwise they report a branch ready to push.

## Usage

The skill only activates when you ask for parallel work. A plain "let's continue" doesn't trigger it.

> Let's continue with our tickets, work in parallel when possible

> Do #12, #13 and #14 at the same time with subagents

> status?

## Install

Ask Claude Code:

> Install the skill from https://github.com/DannyKuk/parallel-work

Or clone it into your skills folder:

```sh
git clone https://github.com/DannyKuk/parallel-work ~/.claude/skills/parallel-work
```

Update with `git -C ~/.claude/skills/parallel-work pull`. New sessions pick up changes; running ones keep the version they started with.

Requires `git` and the [GitHub CLI](https://cli.github.com) (`gh`), logged in to the repo you're working on.

## Customize

- **Routing:** edit the table in [`SKILL.md`](SKILL.md), section 2, for example to send anything touching auth to `opus`.
- **Concurrency cap:** change the "At most 5 subagents" rule in section 1.
- **Stale threshold:** `STALE_MIN=20 bash scripts/status.sh` (default 15 minutes).

Logs live in `.parallel-work/` at the repo root. The skill adds that folder to `.git/info/exclude`, so it never gets committed.
