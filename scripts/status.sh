#!/usr/bin/env bash
# Summarize subagent progress logs written under the parallel-work skill.
# Usage: bash status.sh [log-dir]   (default: <git root>/.parallel-work/agents)
# Each log: line 1 is a "# key=value ..." header written by the main agent;
# later lines are "HH:MM | phase | note" appended by the subagent.
set -u

dir="${1:-}"
if [ -z "$dir" ]; then
  root="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's#/\.git$##')"
  [ -n "$root" ] || root="$PWD"
  dir="$root/.parallel-work/agents"
fi

if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
  echo "No agent logs in $dir"
  exit 0
fi

STALE_MIN="${STALE_MIN:-15}"
now=$(date +%s)
# GNU form first: GNU stat accepts "-f %m" but prints filesystem info instead.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

printf '%-22s %-15s %-9s %-7s %s\n' "AGENT" "MODEL/EFFORT" "STATE" "QUIET" "LAST UPDATE"
for f in "$dir"/*.log; do
  [ -e "$f" ] || continue
  name="$(basename "$f" .log)"
  header="$(head -n 1 "$f")"
  model="$(sed -n 's/.*model=\([^ ]*\).*/\1/p' <<<"$header")"
  effort="$(sed -n 's/.*effort=\([^ ]*\).*/\1/p' <<<"$header")"
  last="$(grep -v '^#' "$f" | grep -v '^[[:space:]]*$' | tail -n 1)"
  [ -n "$last" ] || last="(no update yet)"
  quiet=$(( (now - $(mtime "$f")) / 60 ))

  state="running"
  case "$last" in
    *"| DONE"*)    state="done" ;;
    *"| BLOCKED"*) state="BLOCKED" ;;
    *"| FAILED"*)  state="FAILED" ;;
  esac
  if [ "$state" = "running" ] && [ "$quiet" -ge "$STALE_MIN" ]; then
    state="STALE?"
  fi

  printf '%-22s %-15s %-9s %-7s %s\n' "$name" "${model:-?}/${effort:-?}" "$state" "${quiet}m" "$last"
done
