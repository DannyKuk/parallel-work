---
name: parallel-work
description: Use only when the user explicitly asks to work in parallel or to use subagents for tickets/issues (e.g. "work in parallel when possible", "spin up agents for these issues"), or asks for status on agents started this way. Not for a plain "continue", "keep going", or working on the next ticket alone.
license: MIT
---

# Parallel Work

## Overview

Work a ticket backlog with background subagents, where **you pick each subagent's model and effort**, and **every subagent writes a progress log**, so a status check comes from files, not guesses.

This skill is your explicit instruction to set `model` and `effort` on every Agent call. Leaving them out hands every task the main session's model and effort, which is the failure this skill exists to fix.

Invoked as `/parallel-work <args>`: issue numbers (`12 14 15`, `#12 #14`) are the batch: fetch just those with `gh issue view`, then continue at section 1, point 2 (shared files, cap). `status` is a status request (section 4). Any other text is the user's request. No args: start at step 1.

## 1. Pick the batch

1. `gh issue list --state open --json number,title,labels,assignees,body --limit 30`. Skip issues assigned to someone else or labeled blocked/in-progress.
2. Parallel when tickets touch **disjoint files/modules** (check with a quick grep, not just the titles). If ticket B builds on code ticket A creates, or both touch the same files: **one agent does A then B**, one commit per ticket. That avoids B's worktree starting without A's code.
3. **At most 5 subagents running at once**, counting every kind (implementers, reviewers, lookups). Use more only if the user names a number ("use 6 subagents") or says "as many as possible". More tickets than free slots: list the rest as `queued` in the plan, and start the next one each time an agent finishes.
4. A ticket you can finish in a couple of tool calls (typo, one-line config): do it yourself while the agents run, with no agent and no log.

## 2. Route each ticket

| Ticket looks like | model | effort |
|---|---|---|
| Read-only lookup, triage, summarizing, typo/docs, version bump, rename | `haiku` | `low` |
| Clear acceptance criteria, follows an existing pattern, few files | `sonnet` | `medium` |
| Clear spec but tricky logic, many files, or unfamiliar subsystem | `sonnet` | `high` |
| Ambiguous spec, design/architecture, cross-cutting refactor, security, concurrency, data migration, **unknown root cause** | `opus` | `high` |
| Already failed once at a lower tier | one tier up (`haiku`→`sonnet`→`opus`, up to `high`) | |
| Reviewing a finished agent's diff (see section 5) | `opus` | `high` |

- **`xhigh` and `max` need the user's explicit yes, every time.** They cost several times more tokens, and a failed `opus`/`high` run usually means the ticket is unclear, not that more thinking is needed. Propose it in one line (what failed, what the agent learned, why you think xhigh would help, or what question the user could answer instead). Keep the other tickets moving while you wait. Never escalate past `opus`/`high` on your own.
- When unsure between two rows, take the higher one. A failed cheap run costs more than one right-sized run.
- **Agent types:** implementers use `subagent_type: "parallel-implementer"` and reviewers use `"parallel-reviewer"` (read-only). Both ship in this skill's `agents/` folder. If they aren't in your available agent types, use `general-purpose` with the same briefs, and tell the user once: `mkdir -p ~/.claude/agents && ln -sf <this skill's base dir>/agents/*.md ~/.claude/agents/` (restart Claude Code if that folder is new).
- Always pass `model` and `effort` on the call: they override the agent file's defaults. Never use `subagent_type: "fork"` for routed work: forks ignore `model` and `effort`.

Before dispatching, show the user the plan as a table:

```
#42 Orders pagination   → sonnet / medium  (existing pattern, clear AC)
#43 Queue deadlock      → opus / high      (unknown root cause)
#44 Customers pagination→ same agent as #42 (reuses the paginator #42 creates)
#41 README typo         → me, inline
```

Then dispatch in the same turn. The user's request to work in parallel is the go-ahead, so don't wait for a yes.

## 3. Set up logs, then dispatch

Do this once per session, from the main checkout:

```bash
ROOT="$(git rev-parse --show-toplevel)"; mkdir -p "$ROOT/.parallel-work/agents"
grep -qx '.parallel-work/' "$ROOT/.git/info/exclude" || echo '.parallel-work/' >> "$ROOT/.git/info/exclude"
```

Logs left over from an earlier batch would show up in every status check, so move them out of the way when you start a new batch (`status.sh` skips subfolders). Not when you pick up an unfinished one (section 6):

```bash
mkdir -p "$ROOT/.parallel-work/agents/done"
find "$ROOT/.parallel-work/agents" -maxdepth 1 -type f -exec mv {} "$ROOT/.parallel-work/agents/done/" \;
```

For each agent, write the log header **before** dispatching it (slug = `<issue>-<short-name>`):

```bash
echo "# ticket=#42 model=sonnet effort=medium dispatched=$(date +%H:%M)" > "$ROOT/.parallel-work/agents/42-orders-pagination.log"
```

Send all agents of the batch in **one message** (they run in the background automatically), each with `subagent_type: "parallel-implementer"`, `model`, `effort`, and `isolation: "worktree"`. Every brief contains these parts, in order:

1. Goal: issue number, title, the acceptance criteria copied from the issue
2. Context: relevant files, patterns to follow, what is already ruled out, which paths other agents own (hands off)
3. Done means: tests pass, committed on branch `issue-<n>-<slug>` (or the repo's own branch naming, if CLAUDE.md or CONTRIBUTING sets one). Don't push: the main session pushes after review.
4. The progress-log block below, with the **absolute** log path filled in

```
PROGRESS LOG (required). After each milestone, append one line:
  printf '%s | %s | %s\n' "$(date +%H:%M)" "<phase>" "<one-line note>" >> <ABS_LOG_PATH>
Use printf, not echo: zsh's echo turns a backslash in the note (\0, \b) into a control byte.
Phase names are free-form. Typical: started, plan, tests, implementing, verifying, pr.
For debugging: reproduce, isolate, root-cause, fix, verifying.
Log at least every ~10 minutes of work. The last line must be DONE, BLOCKED or FAILED
with the reason, branch or PR link. If the write is denied, keep working and put the
milestones in your final report instead.
```

## 4. While agents run

- **Status request** ("status?", "how far are they?"): run `bash <this skill's base dir>/scripts/status.sh` from the main checkout (it finds `.parallel-work/agents` via git; an optional argument overrides the dir). Report from its output: one row per ticket with model/effort, state, last update, minutes quiet, plus tickets you did inline or that are queued. Model/effort is always the **implementer's**, also once review starts: the reviewer is always `opus` · `high`, so fold its `-review` log into the ticket's row as state (`in review`, `review PASS`, `fix round`) and never write `→ opus review` there. Never say "probably" about an agent's progress; the log either shows it or it doesn't.
- **`STALE?`** (no log line for 15+ minutes): check activity with `git -C <worktree> status --short` and `git -C <worktree> diff --stat`. Changes still appearing: report it as working, just not logging. Nothing for 30+ minutes: tell the user and offer to stop it and re-dispatch one tier up.
- **On each completion notification:** check that `git -C <worktree> diff --stat <base>...HEAD` stays within the ticket's scope (`<base>` = the default branch, from `gh repo view --json defaultBranchRef`). If its own report admits it skipped or changed an acceptance criterion, send it straight back with SendMessage; don't spend a review on a known gap. Otherwise start the tests inside its worktree with `run_in_background: true` and dispatch its reviewer (section 5) in the same turn. Never wait on a test suite in the foreground: a 5-minute run blocks every other agent's report for 5 minutes. A notification saying the agent "is waiting on its own background work" is not a finish: wait for its report or a DONE line in its log. Give a short update on that ticket only (what finished, what happens next), then go to section 5. No status table here: show it only on a status request and at batch end. BLOCKED or FAILED: re-route one tier up and re-dispatch with what was learned.
- When a slot frees up, start the next queued ticket (route it first).
- **Batch end** (every ticket shipped or waiting on the user): clean up the locked worktrees (section 5), show the status table once, then a handoff: per ticket the PR link or branch, and what is still open and who it waits on. Then stop. Don't pull new tickets on your own, also not on a plain "continue". If the user asks for more tickets, suggest a `/clear` first (logs, branches and PRs carry the state, the old context only costs tokens), then start at section 1.

## 5. Review, then ship

Every code-changing ticket gets a fresh reviewer at **`opus` · `high`**, no matter which tier implemented it. A cheap implementer plus a strong reviewer saves tokens on the long work without saving them on correctness. Skip review only for `haiku`-tier work (docs, typos): after the scope check, ship it as on PASS.

Don't read the diff yourself: that fills your context and you're biased by the brief you wrote. Dispatch it with `subagent_type: "parallel-reviewer"`, `model: "opus"`, `effort: "high"`. The reviewer counts toward the 5-agent cap, gets its own log (`<slug>-review.log`, header `# ticket=#<n>-review model=opus effort=high`), and needs no worktree. Its brief, in order:

```
REVIEW #<n> <title>. You review; do not edit files.
Acceptance criteria: <copied from the issue>
Diff: git -C <ABS_WORKTREE> diff <base>...HEAD   (branch issue-<n>-<slug>)
Check: acceptance criteria met, correctness bugs, missing or weak tests,
changes outside the ticket's scope, security and concurrency issues.
Reply: first line PASS or CHANGES, then at most 10 findings as
`file:line: problem; why it matters`. Real defects only, no style nits.
<progress-log block from section 3, with the review log path>
```

Give the reviewer the acceptance criteria and the diff, **not** the implementer's summary: it should judge the code, not the story.

- **PASS (ship), once your background test run is green too:** if the user or CLAUDE.md asked for pushes or PRs, push the branch and open the PR (`Closes #<n>`). Otherwise report the branch as ready to push. Either way, then clean up the worktree (the ticket branch and its commits stay):
  ```bash
  git worktree remove <worktree> && git branch -d worktree-agent-<id>
  ```
  `worktree-agent-<id>` is the branch Claude Code created for the worktree; without the delete these pile up. If `remove` says the worktree is **locked**, Claude Code is still holding it for that agent: leave it, and when the batch ends run `git worktree unlock <worktree>` and the two commands above.
- **CHANGES:** save the reviewer's reply to `$ROOT/.parallel-work/agents/<slug>-findings.md` (so a later session can pick it up), then send the findings to the **original implementer** with SendMessage (it still has its context), and have it fix, commit and report. Its fix-round lines go in the same log (a line after DONE just shows it as running again). Then send the **same reviewer** the new commit range (`git -C <worktree> diff <old-head>..HEAD`) and its open findings with SendMessage to re-check. Leave out the implementer's account of the fix, as in the first review.
- **Any CHANGES on the re-check:** stop and tell the user, with the open findings, the unpushed branch, and the options: they clarify, you re-dispatch the implementer one tier up, or they take it over. No third round without their answer.

## 6. Picking up a batch in a new session

After `/clear` or in a new session, the earlier agents can't be reached with SendMessage, and you remember nothing. Rebuild the state from `status.sh`, `git worktree list` and `gh pr list --author @me`, and keep the logs where they are (same batch). A log that still gets new lines is a live agent: leave it alone. For every other unfinished ticket:

- **Open findings** (`<slug>-findings.md`): the branch is usually still checked out in the old worktree, and a new agent's worktree can't check it out then (it ends on a detached HEAD). If `git -C <old-worktree> status --short` is empty, remove it as in section 5 (`git worktree unlock` first if locked). If it has uncommitted changes, tell the user and leave that ticket. Then dispatch a new implementer at the ticket's tier with the section 3 brief, plus: check out the existing branch `issue-<n>-<slug>` (don't create it), fix exactly these findings (the file's content). Its review is a fresh reviewer with the full `<base>...HEAD` diff and the old findings to re-check. That counts as the re-check round of section 5.
- **No findings, no live agent, no DONE:** the run died. Re-dispatch it as in section 3, on its existing branch if it has commits.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Agent call without `model`/`effort` | Every call sets both, from the routing table |
| Everything routed to `opus`/`high` "to be safe" | Clear, pattern-following tickets go to `sonnet`/`medium` |
| Relative log path in the brief | Worktrees have a different cwd; always pass the absolute path |
| Answering status from memory | Run `status.sh` first |
| Two agents editing the same module | Run them one after another |
| Auto-escalating to `xhigh` after a failure | Ask the user first; often the ticket needs clarifying instead |
| Reading diffs yourself, or letting the implementer self-review | Dispatch the `opus` · `high` reviewer |
| Passing the implementer's summary to the reviewer | Acceptance criteria and diff only |
| Status table shows the reviewer's model, or a separate review row | Implementer's model/effort; review goes in the state column |
| Status table after every completion notification | Short update; the table only on request or when the batch is done |
| Pushing or opening a PR before review passes | Implementers never push; you push after PASS |
| Waiting on a test suite in the foreground | `run_in_background: true`, reviewer dispatched in the same turn |
| Pulling a new batch when the queue empties | Batch end: handoff, then stop. More tickets only on request, after a `/clear` |
| Dispatching a fixer while its branch is checked out in the old worktree | Remove the clean old worktree first (section 6) |
| `git worktree remove` alone | Also `git branch -d worktree-agent-<id>`; a locked worktree waits for the batch's end |
