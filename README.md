# claude-token-counter

A Claude Code `Stop` hook that tracks token usage and cost per call, per session, and across all time — displayed in your terminal after every response.

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
3. Copies `hooks/token_counter.py` to `~/.claude/hooks/`
4. Registers the hook in `~/.claude/settings.json` (merges safely with any existing hooks)
5. Runs a smoke test to confirm everything works

## What it shows

After every Claude Code session stop you'll see a formatted box in your terminal:

```
╭─ Token Usage ─────────────────────────────────────────╮
│  This call   │  Input: 1,200   Output: 340   Cache: 800 read
│              │  Cost:  $0.0089
├──────────────┼───────────────────────────────────────────
│  Session     │  Input: 8,400   Output: 2,100  Cache: 4,200 read
│              │  Cost:  $0.0521   Calls: 7
├──────────────┼───────────────────────────────────────────
│  Total       │  Input: 142,000  Output: 38,000
│              │  Cost:  $1.2340   Calls: 89
╰─────────────────────────────────────────────────────────╯
```

- **This call** — tokens and cost for the most recent response
- **Session** — cumulative totals for the current session ID
- **Total** — cumulative totals across every session ever tracked

Color output is disabled automatically if the `NO_COLOR` environment variable is set or stdout is not a TTY.

## Where data is stored

All usage data is written to:

```
~/.claude/token_usage.json
```

Structure:

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
      "model": "claude-sonnet-4-5",
      "input_tokens": 0,
      "output_tokens": 0,
      "cache_write_tokens": 0,
      "cache_read_tokens": 0,
      "cost_usd": 0.0,
      "calls": 0
    }
  }
}
```

Errors (e.g. malformed hook input) are logged to `~/.claude/token_usage_errors.log`.

## Uninstalling

```bash
bash uninstall.sh
```

The uninstaller removes the hook script and its entry from `~/.claude/settings.json` (all other hooks are preserved). It will ask whether you want to keep your historical usage data.

## Supported models and pricing

| Model prefix        | Input ($/M) | Output ($/M) | Cache Write ($/M) | Cache Read ($/M) |
|---------------------|-------------|--------------|-------------------|------------------|
| `claude-opus-4`     | $15.00      | $75.00       | $18.75            | $1.50            |
| `claude-sonnet-4`   | $3.00       | $15.00       | $3.75             | $0.30            |
| `claude-haiku-4`    | $0.80       | $4.00        | $1.00             | $0.08            |
| `claude-opus-3`     | $15.00      | $75.00       | $18.75            | $1.50            |
| `claude-sonnet-3`   | $3.00       | $15.00       | $3.75             | $0.30            |
| `claude-haiku-3`    | $0.25       | $1.25        | $0.30             | $0.03            |

Model matching uses the longest prefix. If a model name doesn't match any prefix, cost is shown as `unknown (model: <name>)` and no cost is added to totals.

## Contributing / updating prices

Anthropic sometimes adjusts pricing. To update:

1. Edit the `PRICING` dict at the top of `hooks/token_counter.py`
2. Re-run `bash install.sh` to redeploy the updated script

Pull requests welcome. Please keep the implementation stdlib-only and Python 3.6+ compatible.
