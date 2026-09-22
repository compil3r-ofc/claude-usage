---
description: Record the current Weekly · Fable usage into the claude-usage cache
allowed-tools: mcp__ccd_session_mgmt__get_usage, Bash(claude-usage:*), Bash(date:*)
---

Refresh the Fable weekly number that `claude-usage` reports.

The status line collector keeps the 5-hour and weekly-all-models numbers current
on its own, but Claude Code does not expose the per-model (Fable) limit to any
script. This command reads it from the session and writes it into the cache.

**This command only works in the Claude desktop app.** The usage numbers come
from `mcp__ccd_session_mgmt__get_usage`, a tool the desktop app provides. In a
terminal `claude` session that tool does not exist, and there is no scriptable
substitute — the CLI exposes `/usage` interactively but nothing a command can
read. On those machines the 5-hour and weekly numbers still work; Fable simply
shows as not recorded.

Do this:

1. Call `mcp__ccd_session_mgmt__get_usage`. If the tool is not available in this
   session, stop and tell the user that syncing Fable needs the Claude desktop
   app, and that the other two numbers are unaffected. Do not try other tools,
   shell commands or the API to find the number — there is no other source.
2. In `plan.windows`, find the entry whose `label` is `Weekly · Fable`. Take its
   `percentUsed` and `resetsAt` (an ISO-8601 UTC timestamp). Also note `plan.plan`
   (for example `Max`).
   - If no Fable window is present, tell the user their account has no separate
     Fable limit right now and stop — do not write anything.
3. Convert `resetsAt` to Unix epoch seconds. On macOS, dropping the fractional
   seconds and the trailing `Z`:

   TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "2026-09-24T10:00:00" +%s

   Check the result is a positive integer. If the conversion fails or returns
   nothing, stop and tell the user — do not call the command without it. The
   epoch is required, and `claude-usage` rejects a missing or zero value.

4. Run:

   claude-usage --set-fable <percentUsed> <epoch> "<plan>"

   It exits non-zero and prints why if anything is wrong. Check the exit status
   rather than assuming it worked.

5. Run `claude-usage` and show the user the refreshed report.

Report the Fable percentage and when the window resets. Keep it to a line or two.
