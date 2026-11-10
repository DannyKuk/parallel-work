# parallel-work

A Claude Code skill for working through a ticket backlog with parallel subagents. It fixes two problems:

1. **Every subagent runs on the main session's model and effort.** By default, Claude leaves `model` and `effort` unset when it spawns agents, so a typo fix gets the same Opus/high treatment as a deadlock hunt. With this skill, the main agent routes each ticket to a model and effort level (`haiku`/`sonnet`/`opus`, `low` … `xhigh`), tells you its choices, and moves a ticket up a tier if it fails. `xhigh` and `max` are never chosen without your explicit approval. At most 5 subagents run at once unless you say otherwise ("use 8 subagents", "as many as possible"); the rest wait in a queue.
2. **Long-running agents are a black box.** Each subagent appends one-line milestones to `.parallel-work/agents/<ticket>.log`. When you ask "status?", the main agent runs `scripts/status.sh` and reports what the logs actually say, including agents that have gone quiet.

## Install

```bash
git clone https://github.com/DannyKuk/parallel-work ~/.claude/skills/parallel-work
```

Then in any repo with GitHub issues:

> Let's continue with our tickets, work in parallel when possible

It only activates when you explicitly ask for parallel work or subagents. A plain "let's continue" doesn't trigger it.

Before it dispatches anything, you'll see a routing table like this:

```
#42 Orders pagination    → sonnet / medium  (existing pattern, clear AC)
#43 Queue deadlock       → opus / high      (unknown root cause)
```

Ask "status?" at any time:

```
AGENT                  MODEL/EFFORT    STATE     QUIET   LAST UPDATE
42-orders-pagination   sonnet/medium   running   2m      16:30 | tests | 4 failing tests written
43-queue-deadlock      opus/high       STALE?    18m     16:21 | started | reproducing
```

## Customize

The routing table lives in `SKILL.md`, section 2. Edit it to match your preferences, for example to default to `opus` for anything touching auth. `STALE_MIN=20 bash scripts/status.sh` changes the quiet threshold (default 15 minutes).

Logs go in `.parallel-work/` at the repo root. The skill adds that folder to `.git/info/exclude`, so it never gets committed.
