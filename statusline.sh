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

# Previous cache, so we can carry forward the Fable snapshot that the
# status line payload does not include.
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

if [ -n "$merged" ] && [ "$merged" != "null" ]; then
  tmp="$CACHE.$$.tmp"
  printf '%s\n' "$merged" > "$tmp" 2>/dev/null && mv -f "$tmp" "$CACHE" 2>/dev/null
fi

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

