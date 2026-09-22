#!/bin/bash
# The cache is read-modify-written by statusline.sh on every render and by
# `claude-usage --set-fable`. Before both took a lock, a render that read the
# cache just before a sync wrote back a snapshot predating it, losing the Fable
# value the user had just recorded — 32 losses in 40 attempts.
#
# Usage: tests/concurrency.sh [rounds] [concurrent-renders]
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
REPO=$PWD

ROUNDS="${1:-40}"; RENDERS="${2:-4}"
CACHE=$(mktemp -d)/cache.json
export CLAUDE_USAGE_CACHE="$CACHE"

now=$(date +%s)
EPOCH=$(( now + 187200 ))
PAYLOAD='{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":33,"resets_at":'$(( now + 16200 ))'}}}'

lost_fable=0; lost_rate=0; syncfail=0
for _ in $(seq 1 "$ROUNDS"); do
  printf '%s' '{"updated_at":1}' > "$CACHE"
  pids=()
  for _ in $(seq 1 "$RENDERS"); do ( printf '%s' "$PAYLOAD" | "$REPO/statusline.sh" >/dev/null 2>&1 ) & pids+=($!); done
  "$REPO/bin/claude-usage" --set-fable 100 "$EPOCH" Max >/dev/null 2>&1 || syncfail=$((syncfail+1))
  for _ in $(seq 1 "$RENDERS"); do ( printf '%s' "$PAYLOAD" | "$REPO/statusline.sh" >/dev/null 2>&1 ) & pids+=($!); done
  wait "${pids[@]}" 2>/dev/null
  [ "$(/usr/bin/jq -r '.fable.used_percentage // "x"' "$CACHE" 2>/dev/null)" = "x" ] && lost_fable=$((lost_fable+1))
  [ "$(/usr/bin/jq -r '.five_hour.used_percentage // "x"' "$CACHE" 2>/dev/null)" = "x" ] && lost_rate=$((lost_rate+1))
done

locks=$(ls -d "$CACHE".lock 2>/dev/null | wc -l | tr -d ' ')
tmps=$(ls "$CACHE".*.tmp 2>/dev/null | wc -l | tr -d ' ')
rm -rf "$(dirname "$CACHE")"

printf 'rounds=%s renders/round=%s\n' "$ROUNDS" "$(( RENDERS * 2 ))"
printf '  fable lost:    %s\n  rate lost:     %s\n  sync failures: %s\n  leaked locks:  %s\n  leaked tmp:    %s\n' \
  "$lost_fable" "$lost_rate" "$syncfail" "$locks" "$tmps"

if [ "$lost_fable" -eq 0 ] && [ "$lost_rate" -eq 0 ] && [ "$syncfail" -eq 0 ] \
   && [ "$locks" -eq 0 ] && [ "$tmps" -eq 0 ]; then
  echo "All checks passed."; exit 0
fi
echo "FAILED"; exit 1
