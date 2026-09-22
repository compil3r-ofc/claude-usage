# claude-usage

Real-time readout of how much of your Claude plan is left — in the terminal and
in the macOS menu bar.

```
  Claude usage · Max plan

  5-hour             ▓▓▓▓▓▓░░░░░░░░░░░░░░   33%   resets in 4h 30m
  Weekly, all models ▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░   71%   resets in 2d 4h
  Weekly, Fable      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  100%   resets in 2d 4h  (read 3m ago)

  updated just now
```

No credentials, no API calls, no extra token spend.

## How it works

Claude Code pipes a JSON blob to your status line script on every render. For
Pro and Max subscribers that blob carries the live rate-limit numbers. We tee
those into a small cache file, and everything else reads the cache.

```
Claude Code session
      │  stdin JSON (rate_limits.five_hour, rate_limits.seven_day)
      ▼
statusline.sh ──────────────► ~/.claude/usage-cache.json
      │                              │
      │ prints status bar            ├──► claude-usage        (terminal)
      ▼                              └──► ClaudeUsage.app     (menu bar)
 ~/code  main  Opus  ctx 11% │ 5h 33% wk 71% fable 100%
```

Because the cache is just a file, any number of readers can share it and none of
them need to authenticate.

## Install

```bash
git clone https://github.com/compil3r-ofc/claude-usage.git
cd claude-usage && ./install.sh
```

It registers the status line in `~/.claude/settings.json` (backing up what was
there and refusing to overwrite a status line you already use), installs the
`/usage-sync` command, and adds `bin/` to your `PATH`.

**The status line activates on the next new Claude Code session** — `settings.json`
is read at session start. Open a new session and send one message to fill the cache.

For the menu bar app:

```bash
cd menubar && ./build.sh && open ClaudeUsage.app
```

Needs only Xcode Command Line Tools — no Xcode, no Homebrew, no SwiftBar.
To keep it around: `cp -R ClaudeUsage.app /Applications/` and add it under
System Settings → General → Login Items.

## The Fable caveat

Claude Code exposes `five_hour` and `seven_day` to scripts. It does **not**
expose the per-model weekly limit, so Fable cannot be read by any background
process. It is available only inside a session.

So Fable is a *snapshot*: run `/usage-sync` in any Claude Code session and both
readers display the number along with how old the reading is. The other two
windows are always live. Nothing ever shows you a stale number without saying so.

We deliberately did not poll it headlessly — every poll would spend tokens from
the very quota being measured.

## The two surfaces compared

|                      | `claude-usage` (terminal)            | `ClaudeUsage.app` (menu bar)        |
|----------------------|--------------------------------------|-------------------------------------|
| Shows                | all three, bars + countdowns         | tightest window always visible; all three in the dropdown |
| Effort to read       | you type a command                   | zero — it is always on screen       |
| Best for             | checking before a big job; scripting | ambient awareness while you work    |
| Freshness            | reads cache at the moment you ask    | polls every 60s, repaints on open   |
| Scriptable           | yes — `--short`, `--json`, exit codes| no                                  |
| Install cost         | none beyond the repo                 | one `swiftc` build                  |
| Dependencies         | `jq` (Apple ships it at `/usr/bin/jq`) | Xcode Command Line Tools          |
| Works over SSH       | yes                                  | no                                  |

They read the same cache, so they never disagree.

**Which to use:** both. The menu bar answers "am I close to a wall?" without you
asking. The terminal tool answers "exactly how close, and when does it reset?"
and is the one you can pipe into other things.

## Terminal usage

```bash
claude-usage            # full report
claude-usage --short    # 5h 33% · wk 71% · fbl 100%
claude-usage --json     # raw cache
claude-usage sync       # how to refresh the Fable number
```

`--short` is designed to drop into a prompt:

```bash
RPROMPT='$(claude-usage --short 2>/dev/null)'
```

Exit code is non-zero when there is no data, so prompts degrade quietly.

## Menu bar app

The dropdown lists all three windows with bars, reset countdowns and the age of
the Fable reading. Green under 70%, amber 70–89, red at 90+.

**Choosing what sits in the menu bar.** Under `Show in menu bar · pick one` the
dropdown offers four choices as peers — the three windows, then auto:

```
  Show in menu bar  ·  pick one
  5-hour             ▓▓▓▓▓░░░░░░░░░░░   33%
     resets in 4h 29m
  Weekly, all models ▓▓▓▓▓▓▓▓▓▓▓░░░░░   71%
     resets in 2d 3h
  Weekly, Fable      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  100%
     resets in 2d 3h · read 8m ago
✓ Tightest of the three  (auto)
     follows whichever is closest to its limit
```

Click any of the three windows to pin it, or "Tightest of the three" to let the
title follow whichever is closest to its limit — the one that will actually stop
you. That is the default. A checkmark marks the current choice, and it persists
across relaunches.

If you pin Fable before it has ever been synced, the title falls back to the
tightest window and says so rather than showing nothing.

It re-reads the cache every 60 seconds, and always repaints just before the
dropdown opens, so what you see when you click is current.

Run the checks with `menubar/selftest.sh`.

## Sharing with the team

A co-worker clones the repo and runs `./install.sh`, then `cd menubar && ./build.sh`
for the menu bar app.
Requirements: macOS, Claude Code v2.1.x or newer, and a Pro or Max subscription
(the `rate_limits` block is absent on API-key and gateway setups — both readers
say so rather than showing zeros).

## Files

| File | Purpose |
|---|---|
| `statusline.sh` | Status line + the collector that writes the cache |
| `bin/claude-usage` | Terminal reader |
| `commands/usage-sync.md` | `/usage-sync` slash command, records the Fable number |
| `menubar/UsageCore.swift` | Model, cache loader, formatting |
| `menubar/main.swift` | Menu bar UI |
| `menubar/build.sh` | Builds `ClaudeUsage.app` |
| `menubar/selftest.sh` | Checks bars, durations and cache edge cases |
| `install.sh` | Wires it all up |
