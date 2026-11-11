# Contributing

Thanks for helping out. Bug reports, routing ideas and fixes are all welcome.

## What's where

| Path | What it is |
|---|---|
| `SKILL.md` | The skill itself. Claude Code loads all of it into every session that uses the skill. |
| `agents/` | The `parallel-implementer` and `parallel-reviewer` agent types |
| `scripts/status.sh` | Summarizes the agents' progress logs for `status?` |
| `.github/readme/` | README images. These are generated outside this repo, so don't edit them by hand. If your change makes one out of date, say so in the PR. |

## Try your change locally

1. Fork the repo. If you already have the skill installed, move `~/.claude/skills/parallel-work` aside first.
2. Clone your fork into place and link the agents:

   ```sh
   git clone https://github.com/<you>/parallel-work ~/.claude/skills/parallel-work
   mkdir -p ~/.claude/agents && ln -sf ~/.claude/skills/parallel-work/agents/*.md ~/.claude/agents/
   ```

3. Start a **new** Claude Code session, because running sessions keep the version they started with. Use a scratch repo that has two or three small GitHub issues.
4. Ask for parallel work ("do #1 and #2 in parallel"), then check:
   - The plan table routes each ticket the way you expect.
   - Logs show up in `.parallel-work/agents/`.
   - `status?` reports one row per ticket.
   - Review runs before anything gets pushed.

## Guidelines

- **Keep `SKILL.md` short.** Every line costs tokens in every session that uses the skill. Change an existing rule before you add a new one, and keep the wording direct.
- **`status.sh` runs everywhere.** That means macOS (bash 3.2, BSD `stat`/`sed`), Linux, and Git Bash on Windows (GNU tools). Avoid bash 4+ features and GNU-only flags, or provide a fallback the way `mtime()` does. Run `shellcheck scripts/status.sh` before you open the PR.
- **One change per PR.** In the description, say what you tested and on which OS.

## Reporting bugs

Use the bug report template. The most useful things to include are the plan table or `status?` output and what you expected instead. Report security problems privately through [Security → Report a vulnerability](https://github.com/DannyKuk/parallel-work/security/advisories/new), not in a public issue.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
