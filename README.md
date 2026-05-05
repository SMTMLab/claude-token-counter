# claude-token-counter

Token usage and cost tracker for Claude Code — displayed live in the status bar after every response.

## Requirements

- Python 3.6+ (stdlib only — no pip installs needed)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and initialized (`~/.claude/` must exist)
- macOS, Linux, or WSL (Windows Git Bash is **not** supported)

## Installation

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/smtmlab/claude-token-counter/main/install.sh | bash
```

### Manual

```bash
git clone https://github.com/smtmlab/claude-token-counter.git
cd claude-token-counter
bash install.sh
```

The installer:

1. Detects your platform (macOS / Linux / WSL)
2. Verifies `python3` is available
3. Copies all three hook scripts to `~/.claude/hooks/`
4. Registers hooks (`Stop`, `UserPromptSubmit`, `SessionStart`) in `~/.claude/settings.json`
5. Configures the `statusLine` command
6. Runs a smoke test

## What it shows

Data appears in Claude Code's status bar at the bottom of the terminal after every response:

```
session: $0.0521 · 8k↑ 2k↓ 4M⚡ · 7 calls · 12% ctx  ·  total: $1.2340 · 142k↑ 38k↓ 800M⚡ · 89 calls
```

| Field | Description |
|-------|-------------|
| `$0.0521` | Session cost so far |
| `8k↑` | Session input tokens |
| `2k↓` | Session output tokens |
| `4M⚡` | Session cache-read tokens |
| `7 calls` | API calls this session |
| `12% ctx` | Context window used by last call |

**Context window color coding:**

| Color | Meaning |
|-------|---------|
| Green | < 40% — plenty of room |
| Yellow | 40–65% — getting full |
| Red + `⚠ /save` | ≥ 65% — compaction approaching, save your session |

> Claude Code compacts at ~80%. The warning fires at 65% to give you time to `/save`.

### Multiple windows

Each Claude Code window tracks its own session independently using the shell's `$PPID` as a stable identifier. Opening a new window starts fresh with no session data shown until the first response arrives.

### `/clear` resets the session

Running `/clear` blanks the session counters immediately. The `SessionStart` hook (fired by Claude Code with `source: "clear"`) zeroes the session in storage before the next render.

## How it works

Three hook scripts cooperate:

| Script | Hook | Purpose |
|--------|------|---------|
| `token_counter.py` | `Stop` | Reads token usage from the transcript, calculates cost, writes to `token_usage.json` |
| `token_session_init.py` | `UserPromptSubmit` + `SessionStart` | Pins the current session to the window via a `$PPID`-keyed temp file; resets session on `/clear` |
| `token_statusline.py` | `statusLine` command | Reads `token_usage.json` and renders the status bar string |

## Where data is stored

```
~/.claude/token_usage.json       # usage data
~/.claude/token_usage_errors.log # hook errors
/tmp/claude_session_<ppid>       # per-window session pin (session_id + transcript path)
```

`token_usage.json` structure:

```json
{
  "total": {
    "input_tokens": 0,
    "output_tokens": 0,
    "cache_write_tokens": 0,
    "cache_read_tokens": 0,
    "cost_usd": 0.0,
    "calls": 0
  },
  "sessions": {
    "<session_id>": {
      "started_at": "2025-05-05T10:00:00",
      "last_updated": "2025-05-05T10:30:00",
      "model": "claude-sonnet-4-6",
      "input_tokens": 0,
      "output_tokens": 0,
      "cache_write_tokens": 0,
      "cache_read_tokens": 0,
      "cost_usd": 0.0,
      "calls": 0,
      "last_input_tokens": 0,
      "last_cache_write_tokens": 0,
      "last_cache_read_tokens": 0
    }
  }
}
```

## Uninstalling

```bash
bash uninstall.sh
```

Removes hook scripts and their entries from `~/.claude/settings.json`. Prompts before deleting historical usage data.

## Supported models and pricing

| Model prefix | Input ($/M) | Output ($/M) | Cache Write ($/M) | Cache Read ($/M) |
|---|---|---|---|---|
| `claude-opus-4` | $15.00 | $75.00 | $18.75 | $1.50 |
| `claude-sonnet-4` | $3.00 | $15.00 | $3.75 | $0.30 |
| `claude-haiku-4` | $0.80 | $4.00 | $1.00 | $0.08 |
| `claude-opus-3` | $15.00 | $75.00 | $18.75 | $1.50 |
| `claude-sonnet-3` | $3.00 | $15.00 | $3.75 | $0.30 |
| `claude-haiku-3` | $0.25 | $1.25 | $0.30 | $0.03 |

Model matched by longest prefix. Unknown models show no cost.

## Contributing / updating prices

1. Edit the `PRICING` dict in `hooks/token_counter.py`
2. Re-run `bash install.sh` to redeploy

Pull requests welcome. Keep implementation stdlib-only and Python 3.6+ compatible.
