#!/bin/bash
# peon-ping-lite: Minimal Mac-only sound hook for Claude Code
# Plays CESP pack sounds via afplay when Claude Code fires hook events.
set -uo pipefail

PEON_DIR="${CLAUDE_PEON_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# Check common pack locations if packs/ not in script dir
if [ ! -d "$PEON_DIR/packs" ]; then
  if [ -d "$HOME/.openpeon/packs" ]; then
    PEON_DIR="$HOME/.openpeon"
  else
    _hooks_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/peon-ping-lite"
    [ -d "$_hooks_dir/packs" ] && PEON_DIR="$_hooks_dir"
    unset _hooks_dir
  fi
fi
CONFIG="$PEON_DIR/config.json"
STATE="$PEON_DIR/.state.json"

# --- Read stdin (hook JSON) ---
INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

# --- Kill any previously playing peon-ping sound ---
kill_previous_sound() {
  local pidfile="$PEON_DIR/.sound.pid"
  if [ -f "$pidfile" ]; then
    local old_pid
    old_pid=$(cat "$pidfile" 2>/dev/null)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null
    fi
    rm -f "$pidfile"
  fi
}

# --- Play sound with afplay ---
play_sound() {
  local file="$1" vol="$2"
  kill_previous_sound
  if [ "${PEON_TEST:-0}" = "1" ]; then
    afplay -v "$vol" "$file" >/dev/null 2>&1
  else
    nohup afplay -v "$vol" "$file" >/dev/null 2>&1 &
    echo "$!" > "$PEON_DIR/.sound.pid"
  fi
}

# --- Single Python call: config, event parsing, category routing, sound picking ---
eval "$(python3 -c "
import sys, json, os, random, time, shlex
q = shlex.quote

config_path = '$CONFIG'
state_file = '$STATE'
peon_dir = '$PEON_DIR'
state_dirty = False

# --- Load config ---
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}

if str(cfg.get('enabled', True)).lower() == 'false':
    print('PEON_EXIT=true')
    sys.exit(0)

volume = cfg.get('volume', 0.5)
active_pack = cfg.get('active_pack', 'peon')
annoyed_threshold = int(cfg.get('annoyed_threshold', 3))
annoyed_window = float(cfg.get('annoyed_window_seconds', 10))
cats = cfg.get('categories', {})
cat_enabled = {}
for c in ['session.start','task.complete','task.error','input.required','resource.limit','user.spam']:
    cat_enabled[c] = str(cats.get(c, True)).lower() == 'true'

# --- Parse event JSON from stdin ---
event_data = json.load(sys.stdin)
event = event_data.get('hook_event_name', '')
session_id = event_data.get('session_id', '')

# --- Load state ---
try:
    state = json.load(open(state_file))
except Exception:
    state = {}

# --- Event routing ---
category = ''

if event == 'SessionStart':
    if event_data.get('source', '') == 'compact':
        print('PEON_EXIT=true')
        sys.exit(0)
    category = 'session.start'
elif event == 'UserPromptSubmit':
    if cat_enabled.get('user.spam', True):
        all_ts = state.get('prompt_timestamps', {})
        if isinstance(all_ts, list):
            all_ts = {}
        now = time.time()
        ts = [t for t in all_ts.get(session_id, []) if now - t < annoyed_window]
        ts.append(now)
        all_ts[session_id] = ts
        state['prompt_timestamps'] = all_ts
        state_dirty = True
        if len(ts) >= annoyed_threshold:
            category = 'user.spam'
elif event == 'Stop':
    category = 'task.complete'
    # Debounce rapid Stop events
    now = time.time()
    last_stop = state.get('last_stop_time', 0)
    if now - last_stop < 5:
        category = ''
    state['last_stop_time'] = now
    state_dirty = True
elif event == 'PermissionRequest':
    category = 'input.required'
elif event == 'PostToolUseFailure':
    if event_data.get('tool_name', '') == 'Bash' and event_data.get('error', ''):
        category = 'task.error'
    else:
        print('PEON_EXIT=true')
        sys.exit(0)
elif event == 'PreCompact':
    category = 'resource.limit'
elif event == 'SessionEnd':
    # Clean up state for this session
    for key in ('prompt_timestamps',):
        d = state.get(key, {})
        if session_id in d:
            del d[session_id]
            state[key] = d
    os.makedirs(os.path.dirname(state_file) or '.', exist_ok=True)
    json.dump(state, open(state_file, 'w'))
    print('PEON_EXIT=true')
    sys.exit(0)
else:
    print('PEON_EXIT=true')
    sys.exit(0)

# --- Suppress sounds during session replay (claude -c) ---
now = time.time()
if event == 'SessionStart':
    session_starts = state.get('session_start_times', {})
    session_starts[session_id] = now
    state['session_start_times'] = session_starts
    state_dirty = True
elif category:
    session_starts = state.get('session_start_times', {})
    start_time = session_starts.get(session_id, 0)
    if start_time and (now - start_time) < 3:
        category = ''

# --- Check if category is enabled ---
if category and not cat_enabled.get(category, True):
    category = ''

# --- Pick sound ---
sound_file = ''
if category:
    pack_dir = os.path.join(peon_dir, 'packs', active_pack)
    try:
        manifest = None
        for mname in ('openpeon.json', 'manifest.json'):
            mpath = os.path.join(pack_dir, mname)
            if os.path.exists(mpath):
                manifest = json.load(open(mpath))
                break
        if not manifest:
            manifest = {}
        sounds = manifest.get('categories', {}).get(category, {}).get('sounds', [])
        if sounds:
            last_played = state.get('last_played', {})
            last_file = last_played.get(category, '')
            candidates = sounds if len(sounds) <= 1 else [s for s in sounds if s['file'] != last_file]
            pick = random.choice(candidates)
            last_played[category] = pick['file']
            state['last_played'] = last_played
            state_dirty = True
            file_ref = str(pick.get('file', ''))
            if '/' in file_ref:
                candidate = os.path.realpath(os.path.join(pack_dir, file_ref))
            else:
                candidate = os.path.realpath(os.path.join(pack_dir, 'sounds', file_ref))
            pack_root = os.path.realpath(pack_dir) + os.sep
            if candidate.startswith(pack_root):
                sound_file = candidate
    except Exception:
        pass

# --- Write state once ---
if state_dirty:
    os.makedirs(os.path.dirname(state_file) or '.', exist_ok=True)
    json.dump(state, open(state_file, 'w'))

# --- Output shell variables ---
print('PEON_EXIT=false')
print('SOUND_FILE=' + q(sound_file))
print('VOLUME=' + q(str(volume)))
" <<< "$INPUT" 2>/dev/null)"

# If Python signalled early exit, bail out
[ "${PEON_EXIT:-true}" = "true" ] && exit 0

# --- Play sound ---
if [ -n "${SOUND_FILE:-}" ] && [ -f "$SOUND_FILE" ]; then
  if [ "${PEON_TEST:-0}" = "1" ]; then
    play_sound "$SOUND_FILE" "$VOLUME"
  else
    play_sound "$SOUND_FILE" "$VOLUME" & disown
  fi
fi
