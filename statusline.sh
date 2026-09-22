#!/bin/bash
# Claude Code status line + usage collector.
#
# Claude Code pipes session JSON to this script on stdin on every render.
# We do two things with it:
#   1. merge the rate-limit numbers into ~/.claude/usage-cache.json
#      (so `claude-usage` in any terminal can read them)
#   2. print a one-line status bar
#
# rate_limits is only present for Pro/Max subscribers, and only after the
# session's first API response, so every field is treated as optional.

set -uo pipefail

CACHE="${CLAUDE_USAGE_CACHE:-$HOME/.claude/usage-cache.json}"
JQ=/usr/bin/jq
command -v "$JQ" >/dev/null 2>&1 || JQ=jq

input=$(cat)
[ -z "$input" ] && exit 0

now=$(date +%s)
mkdir -p "$(dirname "$CACHE")"

# This cache is read-modify-written here and by `claude-usage --set-fable`.
# Without a lock, a render that read the cache just before a sync writes back a
# snapshot predating it and silently drops the Fable value the user just
# recorded. Measured at 32 losses in 40 attempts under contention, and renders
# are frequent, so this is reached in normal use. mkdir is atomic, so the lock
# is a directory.
LOCK="$CACHE.lock"
locked=0
lock_release() { [ "$locked" = 1 ] && rmdir "$LOCK" 2>/dev/null; locked=0; }
lock_acquire() {   # $1 = attempts, ~20ms apart
  local i=0 age
  while [ "$i" -lt "$1" ]; do
    if mkdir "$LOCK" 2>/dev/null; then
      locked=1; trap lock_release EXIT INT TERM; return 0
    fi
    # Reclaim a lock left behind by a process that died holding it.
    age=$(( now - $(stat -f %m "$LOCK" 2>/dev/null || echo "$now") ))
    [ "$age" -gt 10 ] && rmdir "$LOCK" 2>/dev/null
    i=$((i + 1))
    sleep 0.02
  done
  return 1
}

# Writers hold the lock for milliseconds, so a short wait catches almost all
# contention. This runs on every render, so it must not stall: if the lock is
# busy we render anyway and skip the cache write, which is always safe because
# the next render (or the 60s refresh) writes instead.
lock_acquire 10 || true

prev='{}'
[ -f "$CACHE" ] && prev=$("$JQ" -c . "$CACHE" 2>/dev/null || echo '{}')

merged=$(printf '%s' "$input" | "$JQ" -c \
  --argjson prev "$prev" \
  --argjson now "$now" \
  '
  # Keep a window with no recorded reset time (there is simply no countdown to
  # show); drop one whose reset time has passed. This rule must match the readers
  # in bin/claude-usage and menubar/UsageCore.swift, or the collector deletes
  # entries they are still displaying.
  def fresh(w):
    if (w|type) != "object" then null
    elif (w.resets_at // 0) <= 0 then w
    elif w.resets_at > $now then w
    else null end;

  ($prev // {}) as $p
  | {
      updated_at: $now,
      five_hour:  (fresh(.rate_limits.five_hour)  // fresh($p.five_hour)),
      seven_day:  (fresh(.rate_limits.seven_day)  // fresh($p.seven_day)),
      spend_limit:(fresh(.rate_limits.spend_limit)// fresh($p.spend_limit)),
      # Fable weekly is NOT in the status line payload; preserve whatever
      # `claude-usage sync` last wrote.
      fable:      fresh($p.fable),
      plan:       ($p.plan // null),
      model:      (.model.display_name // $p.model),
      context_pct:(.context_window.used_percentage // null),
      cwd:        (.workspace.current_dir // .cwd // $p.cwd)
    }
  ' 2>/dev/null)

if [ "$locked" = 1 ] && [ -n "$merged" ] && [ "$merged" != "null" ]; then
  tmp="$CACHE.$$.tmp"
  printf '%s\n' "$merged" > "$tmp" 2>/dev/null && mv -f "$tmp" "$CACHE" 2>/dev/null
  rm -f "$tmp" 2>/dev/null
fi
lock_release

# ---------- render the status line ----------

RESET=$'\033[0m'; DIM=$'\033[2m'
grn=$'\033[32m'; ylw=$'\033[33m'; red=$'\033[31m'; cyn=$'\033[36m'

hue() { # pct -> color
  local p=${1%%.*}
  if   [ "$p" -ge 90 ] 2>/dev/null; then printf '%s' "$red"
  elif [ "$p" -ge 70 ] 2>/dev/null; then printf '%s' "$ylw"
  else printf '%s' "$grn"; fi
}

get() { printf '%s' "$merged" | "$JQ" -r "$1 // empty" 2>/dev/null; }

model=$(get '.model')
ctx=$(get '.context_pct')
dir=$(get '.cwd')
[ -n "$dir" ] && dir="${dir/#$HOME/~}"

branch=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git branch --show-current 2>/dev/null)
fi

out=""
[ -n "$dir" ]    && out+="${cyn}${dir}${RESET}"
[ -n "$branch" ] && out+=" ${DIM}${branch}${RESET}"
[ -n "$model" ]  && out+="  ${model}"
if [ -n "$ctx" ]; then
  c=$(hue "$ctx"); out+="  ${DIM}ctx${RESET} ${c}$(printf '%.0f' "$ctx")%${RESET}"
fi

seg=""
for pair in "five_hour:5h" "seven_day:wk" "fable:fable"; do
  key=${pair%%:*}; lbl=${pair##*:}
  v=$(get ".${key}.used_percentage")
  [ -z "$v" ] && continue
  c=$(hue "$v")
  seg+=" ${DIM}${lbl}${RESET} ${c}$(printf '%.0f' "$v")%${RESET}"
done
[ -n "$seg" ] && out+="  ${DIM}│${RESET} ${seg# }"

# "$out" carries a git branch name, which comes from whatever repo is checked
# out and can contain anything. Passing it as the format would let a branch named
# "%2000000000d" make this script emit two gigabytes on every render.
printf '%s\n' "$out"

