# peon-ping-lite

Minimal Mac-only sound hook for Claude Code. Plays [CESP](https://github.com/PeonPing/openpeon) pack sounds when Claude Code fires hook events. No notifications, no relay, no multi-platform — just `afplay`.

Stripped from [peon-ping](https://github.com/PeonPing/peon-ping) (~2,500 lines) down to ~215 lines.

## Install

```bash
git clone https://github.com/PeonPing/peon-ping-lite.git
cd peon-ping-lite
bash install.sh
```

The installer will:
1. Copy `peon.sh` and `config.json` to `~/.claude/hooks/peon-ping-lite/`
2. Symlink packs from an existing peon-ping or openpeon install (or tell you how to download them)
3. Register hooks in `~/.claude/settings.json`

## Events

| Hook Event | CESP Category | What happens |
|---|---|---|
| `SessionStart` | `session.start` | Greeting sound |
| `Stop` | `task.complete` | Task done sound |
| `PermissionRequest` | `input.required` | Needs approval sound |
| `PostToolUseFailure` | `task.error` | Error sound (Bash only) |
| `PreCompact` | `resource.limit` | Context limit sound |
| `UserPromptSubmit` | `user.spam` | Annoyed sound (rapid prompts) |

## Configure

Edit `~/.claude/hooks/peon-ping-lite/config.json`:

```json
{
  "active_pack": "peon",
  "volume": 0.5,
  "enabled": true,
  "categories": {
    "session.start": true,
    "task.complete": true,
    "task.error": true,
    "input.required": true,
    "resource.limit": true,
    "user.spam": true
  },
  "annoyed_threshold": 3,
  "annoyed_window_seconds": 10
}
```

- **`active_pack`** — Which sound pack to use (must exist in `packs/`)
- **`volume`** — `afplay` volume (0.0–1.0)
- **`enabled`** — Master on/off switch
- **`categories`** — Toggle individual event categories
- **`annoyed_threshold`** / **`annoyed_window_seconds`** — How many prompts within the window triggers the `user.spam` sound

## Test

```bash
echo '{"hook_event_name":"Stop"}' | bash ~/.claude/hooks/peon-ping-lite/peon.sh
```

## Uninstall

```bash
rm -rf ~/.claude/hooks/peon-ping-lite
```

Then remove the `peon-ping-lite` entries from `~/.claude/settings.json` hooks.
