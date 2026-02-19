#!/bin/bash
# peon-ping-lite installer — Mac-only, sounds-only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.claude/hooks/peon-ping-lite"
SETTINGS="$HOME/.claude/settings.json"

echo "Installing peon-ping-lite..."

# --- Create install directory ---
mkdir -p "$INSTALL_DIR"

# --- Copy core files ---
cp "$SCRIPT_DIR/peon.sh" "$INSTALL_DIR/peon.sh"
chmod +x "$INSTALL_DIR/peon.sh"
# Only copy config if not already present (preserve user edits)
[ ! -f "$INSTALL_DIR/config.json" ] && cp "$SCRIPT_DIR/config.json" "$INSTALL_DIR/config.json"

# --- Install packs ---
if [ -d "$INSTALL_DIR/packs" ]; then
  echo "Packs directory already exists, keeping it."
elif [ -f "$SCRIPT_DIR/peon/openpeon.json" ]; then
  # Bundled pack from release tarball
  mkdir -p "$INSTALL_DIR/packs"
  cp -R "$SCRIPT_DIR/peon" "$INSTALL_DIR/packs/peon"
  echo "Installed bundled peon pack."
elif [ -d "$HOME/.claude/hooks/peon-ping/packs" ]; then
  ln -s "$HOME/.claude/hooks/peon-ping/packs" "$INSTALL_DIR/packs"
  echo "Linked packs from peon-ping install."
elif [ -d "$HOME/.openpeon/packs" ]; then
  ln -s "$HOME/.openpeon/packs" "$INSTALL_DIR/packs"
  echo "Linked packs from ~/.openpeon."
else
  echo ""
  echo "No packs found. Install peon-ping first to get packs, then re-run this installer:"
  echo "  curl -fsSL peonping.com/install | bash"
  echo ""
fi

# --- Register hooks in settings.json ---
echo "Registering hooks in settings.json..."

python3 -c "
import json, os

settings_path = '$SETTINGS'
hook_cmd = '$INSTALL_DIR/peon.sh'

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault('hooks', {})

hook_sync = {'type': 'command', 'command': hook_cmd, 'timeout': 10}
hook_async = {'type': 'command', 'command': hook_cmd, 'timeout': 10, 'async': True}

events = ['SessionStart', 'SessionEnd', 'Stop', 'Notification', 'UserPromptSubmit', 'PermissionRequest', 'PostToolUseFailure', 'PreCompact']
sync_events = ('SessionStart',)
bash_only_events = ('PostToolUseFailure',)

for event in events:
    hook = hook_sync if event in sync_events else hook_async
    matcher = 'Bash' if event in bash_only_events else ''
    peon_entry = dict(matcher=matcher, hooks=[hook])
    event_hooks = hooks.get(event, [])
    # Remove existing peon-ping-lite entries
    event_hooks = [
        h for h in event_hooks
        if not any('peon-ping-lite/peon.sh' in hk.get('command', '') for hk in h.get('hooks', []))
    ]
    event_hooks.append(peon_entry)
    hooks[event] = event_hooks

settings['hooks'] = hooks

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
"

echo ""
echo "Done! peon-ping-lite installed to $INSTALL_DIR"
echo "Hooks registered for: SessionStart, SessionEnd, Stop, Notification, UserPromptSubmit, PermissionRequest, PostToolUseFailure, PreCompact"
