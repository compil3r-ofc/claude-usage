#!/bin/bash
# Installer for claude-usage. Safe to re-run.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
JQ=/usr/bin/jq
command -v "$JQ" >/dev/null 2>&1 || JQ=$(command -v jq || true)

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

[ -n "$JQ" ] || { echo "jq is required (macOS 15+ ships it at /usr/bin/jq)"; exit 1; }

# The install path is written into ~/.zshrc and into settings.json's statusLine
# command, and a shell evaluates both. Single-quote it so nothing in the path can
# ever be executed: without this, cloning into a directory named 'x$(curl ...)y'
# would run that substitution in every new shell, permanently. Quoting also makes
# paths containing spaces work, which they previously did not.
shq() { local q=${1//\'/\'\\\'\'}; printf "'%s'" "$q"; }

case "$REPO" in
  *$'\n'*) echo "Install path contains a newline; move the repo elsewhere."; exit 1 ;;
esac
REPO_Q=$(shq "$REPO")

bold "Installing claude-usage"
mkdir -p "$CLAUDE_DIR/commands"

# 1. status line — merged into settings.json, never clobbering what is there.
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
else
  echo '{}' > "$SETTINGS"
fi

existing=$("$JQ" -r '.statusLine.command // empty' "$SETTINGS")
if [ -n "$existing" ] \
   && [ "$existing" != "$REPO_Q/statusline.sh" ] \
   && [ "$existing" != "$REPO/statusline.sh" ]; then
  warn "You already have a status line configured:"
  warn "    $existing"
  warn "Leaving it alone. To collect usage data, add this to that script:"
  warn "    $REPO/statusline.sh   (it reads stdin and passes it through)"
else
  tmp=$(mktemp)
  "$JQ" --arg cmd "$REPO_Q/statusline.sh" \
     '.statusLine = {type:"command", command:$cmd, padding:0}
      | del(.statusLine.refreshInterval)' \
     "$SETTINGS" > "$tmp" && mv -f "$tmp" "$SETTINGS"
  ok "status line registered (backup alongside settings.json)"
  # refreshInterval is deliberately unset. With it, every session re-runs the
  # status line each minute, including ones idle for hours, and writes back the
  # rate limits from its last API response — overwriting fresh numbers with
  # stale ones. Without it the script runs on real events, so each write
  # coincides with that session actually receiving current numbers.
fi

# 2. /usage-sync slash command
cp "$REPO/commands/usage-sync.md" "$CLAUDE_DIR/commands/usage-sync.md"
ok "/usage-sync command installed"

# 3. PATH
LINE="export PATH=$REPO_Q/bin:\"\$PATH\""
# Match on the bare path so an existing line is found whether it was written by
# this version or by the earlier unquoted one, and we never append a duplicate.
if grep -qF "$REPO" "$HOME/.zshrc" 2>/dev/null; then
  ok "PATH already set in ~/.zshrc"
else
  printf '\n# claude-usage\n%s\n' "$LINE" >> "$HOME/.zshrc"
  ok "added to PATH in ~/.zshrc"
fi

chmod +x "$REPO/bin/claude-usage" "$REPO/statusline.sh"

echo
bold "Done. Next:"
echo "  1. Open a new terminal (or: source ~/.zshrc)"
echo "  2. Send one message in any Claude Code session — that fills the cache"
echo "  3. Run: claude-usage"
echo
echo "  For the Fable number, run /usage-sync inside a Claude Code session."
