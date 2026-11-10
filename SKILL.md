---
name: parallel-work
description: Use when the user asks to continue with tickets or issues, work through a GitHub backlog, or "work in parallel when possible"; when dispatching several subagents for implementation work; or when the user asks for a status update or progress on running subagents.
---

# Parallel Work

## Overview

Work a ticket backlog with background subagents, where **you pick each subagent's model and effort**, and **every subagent writes a progress log**, so a status check comes from files, not guesses.

This skill is your explicit instruction to set `model` and `effort` on every Agent call. Leaving them out hands every task the main session's model and effort, which is the failure this skill exists to fix.

## 1. Pick the batch

1. `gh issue list --state open --json number,title,labels,assignees,body --limit 30`. Skip issues assigned to someone else or labeled blocked/in-progress.
2. Parallel when tickets touch **disjoint files/modules** (check with a quick grep, not just the titles). If ticket B builds on code ticket A creates, or both touch the same files: **one agent does A then B**, one commit per ticket. That avoids B's worktree starting without A's code.
3. Batch size: at most 4 code-writing agents at once unless the user says otherwise.
4. A ticket you can finish in a couple of tool calls (typo, one-line config): do it yourself while the agents run, with no agent and no log.

## 2. Route each ticket

| Ticket looks like | model | effort |
|---|---|---|
| Read-only lookup, triage, summarizing, typo/docs, version bump, rename | `haiku` | `low` |
| Clear acceptance criteria, follows an existing pattern, few files | `sonnet` | `medium` |
| Clear spec but tricky logic, many files, or unfamiliar subsystem | `sonnet` | `high` |
| Ambiguous spec, design/architecture, cross-cutting refactor, security, concurrency, data migration, **unknown root cause** | `opus` | `high` |
| Already failed once at a lower tier | one tier up (`haiku`→`sonnet`→`opus`, up to `high`) | |
| Reviewing a finished agent's diff | `sonnet` `high` (`opus` `high` if risky) | |

- **`xhigh` and `max` need the user's explicit yes, every time.** They cost several times more tokens, and a failed `opus`/`high` run usually means the ticket is unclear, not that more thinking is needed. Propose it in one line (what failed, what the agent learned, why you think xhigh would help, or what question the user could answer instead). Keep the other tickets moving while you wait. Never escalate past `opus`/`high` on your own.
- When unsure between two rows, take the higher one. A failed cheap run costs more than one right-sized run.
- Never use `subagent_type: "fork"` for routed work: forks ignore `model` and `effort`. Use `general-purpose` with a full brief.

Before dispatching, show the user the plan as a table:

```
#42 Orders pagination   → sonnet / medium  (existing pattern, clear AC)
#43 Queue deadlock      → opus / high      (unknown root cause)
#44 Customers pagination→ same agent as #42 (reuses the paginator #42 creates)
#41 README typo         → me, inline
```

Then dispatch in the same turn. "Continue with our tickets" is the go-ahead, so don't wait for a yes.

## 3. Set up logs, then dispatch

Do this once per session, from the main checkout:

```bash
ROOT="$(git rev-parse --show-toplevel)"; mkdir -p "$ROOT/.parallel-work/agents"
grep -qx '.parallel-work/' "$ROOT/.git/info/exclude" || echo '.parallel-work/' >> "$ROOT/.git/info/exclude"
```

For each agent, write the log header **before** dispatching it (slug = `<issue>-<short-name>`):

```bash
echo "# ticket=#42 model=sonnet effort=medium dispatched=$(date +%H:%M)" > "$ROOT/.parallel-work/agents/42-orders-pagination.log"
```

Send all agents of the batch in **one message** (they run in the background automatically), each with `subagent_type: "general-purpose"`, `model`, `effort`, and `isolation: "worktree"` for code-writing agents. Every brief contains these parts, in order:

1. Goal: issue number, title, the acceptance criteria copied from the issue
2. Context: relevant files, patterns to follow, what is already ruled out, which paths other agents own (hands off)
3. Done means: tests pass, committed on branch `issue-<n>-<slug>`. Add "push and open a PR (`Closes #<n>`)" only if the user or CLAUDE.md has asked for PRs. Otherwise the branch is reported ready to push.
4. The progress-log block below, with the **absolute** log path filled in

```
PROGRESS LOG (required). After each milestone, append one line:
  echo "$(date +%H:%M) | <phase> | <one-line note>" >> <ABS_LOG_PATH>
Phase names are free-form. Typical: started, plan, tests, implementing, verifying, pr.
For debugging: reproduce, isolate, root-cause, fix, verifying.
Log at least every ~10 minutes of work. The last line must be DONE, BLOCKED or FAILED
with the reason, branch or PR link. If the write is denied, keep working and put the
milestones in your final report instead.
```

## 4. While agents run

- **Status request** ("status?", "how far are they?"): run `bash <this skill's base dir>/scripts/status.sh` from the main checkout (it finds `.parallel-work/agents` via git; an optional argument overrides the dir). Report from its output: one row per agent with model/effort, state, last update, minutes quiet, plus tickets you did inline or that are queued. Never say "probably" about an agent's progress; the log either shows it or it doesn't.
- **`STALE?`** (no log line for 15+ minutes): check activity with `git -C <worktree> status --short` and `git -C <worktree> diff --stat`. Changes still appearing: report it as working, just not logging. Nothing for 30+ minutes: tell the user and offer to stop it and re-dispatch one tier up.
- **On each completion notification:** verify the claim yourself (run the tests on its branch, check the PR exists if one was promised), then give a one-line update plus the status table. For `opus`-tier tickets or large diffs, also dispatch a reviewer (routing table, last row) before calling it done. BLOCKED or FAILED: re-route one tier up and re-dispatch with what was learned.
- When a batch finishes and the user asked to continue, start the next batch at step 1.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Agent call without `model`/`effort` | Every call sets both, from the routing table |
| Everything routed to `opus`/`high` "to be safe" | Clear, pattern-following tickets go to `sonnet`/`medium` |
| Relative log path in the brief | Worktrees have a different cwd; always pass the absolute path |
| Answering status from memory | Run `status.sh` first |
| Two agents editing the same module | Run them one after another |
| Auto-escalating to `xhigh` after a failure | Ask the user first; often the ticket needs clarifying instead |
