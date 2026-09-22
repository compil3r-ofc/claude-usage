---
description: Record the current Weekly · Fable usage into the claude-usage cache
allowed-tools: mcp__ccd_session_mgmt__get_usage, Bash(claude-usage:*), Bash(date:*)
---

Refresh the Fable weekly number that `claude-usage` reports.

The status line collector keeps the 5-hour and weekly-all-models numbers current
on its own, but Claude Code does not expose the per-model (Fable) limit to any
script. This command reads it from the session and writes it into the cache.

Do this:

1. Call `mcp__ccd_session_mgmt__get_usage`.
2. In `plan.windows`, find the entry whose `label` is `Weekly · Fable`. Take its
   `percentUsed` and `resetsAt` (an ISO-8601 UTC timestamp). Also note `plan.plan`
   (for example `Max`).
   - If no Fable window is present, tell the user their account has no separate
     Fable limit right now and stop — do not write anything.
3. Convert `resetsAt` to Unix epoch seconds. On macOS, dropping the fractional
   seconds and the trailing `Z`:

   TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "2026-09-24T10:00:00" +%s

4. Run:

   claude-usage --set-fable <percentUsed> <epoch> "<plan>"

5. Run `claude-usage` and show the user the refreshed report.

Report the Fable percentage and when the window resets. Keep it to a line or two.
