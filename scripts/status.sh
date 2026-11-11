#!/usr/bin/env bash
# Summarize subagent progress logs written under the parallel-work skill.
# Usage: bash status.sh [log-dir]   (default: <git root>/.parallel-work/agents)
# Logs moved into a subfolder (e.g. agents/done/) are not listed.
# Each log: line 1 is a "# key=value ..." header written by the main agent;
# later lines are "HH:MM | phase | note" appended by the subagent.
set -u

dir="${1:-}"
if [ -z "$dir" ]; then
  root="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's#/\.git$##')"
  [ -n "$root" ] || root="$PWD"
  dir="$root/.parallel-work/agents"
fi

if [ ! -d "$dir" ] || [ -z "$(find "$dir" -maxdepth 1 -name '*.log' 2>/dev/null)" ]; then
  echo "No agent logs in $dir"
  exit 0
fi

STALE_MIN="${STALE_MIN:-15}"
now=$(date +%s)
# GNU form first: GNU stat accepts "-f %m" but prints filesystem info instead.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

# Drop control bytes (NUL, backspace, ...) before grep sees the log: zsh's echo
# turns a "\0" in a note into a real NUL, and BSD grep then calls the file binary.
clean() { LC_ALL=C tr -d '\000-\010\013-\037\177' < "$1"; }

# Size the name column to the longest log name (review logs run long).
w=22
for f in "$dir"/*.log; do
  [ -e "$f" ] || continue
  n="$(basename "$f" .log)"
  [ "${#n}" -gt "$w" ] && w="${#n}"
done

printf "%-${w}s %-15s %-9s %-7s %s\n" "AGENT" "MODEL/EFFORT" "STATE" "QUIET" "LAST UPDATE"
for f in "$dir"/*.log; do
  [ -e "$f" ] || continue
  name="$(basename "$f" .log)"
  header="$(clean "$f" | head -n 1)"
  model="$(sed -n 's/.*model=\([^ ]*\).*/\1/p' <<<"$header")"
  effort="$(sed -n 's/.*effort=\([^ ]*\).*/\1/p' <<<"$header")"
  last="$(clean "$f" | grep -v '^#' | grep -v '^[[:space:]]*$' | tail -n 1)"
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

  printf "%-${w}s %-15s %-9s %-7s %s\n" "$name" "${model:-?}/${effort:-?}" "$state" "${quiet}m" "$last"
done
