#!/usr/bin/env python3
import json, os, sys

CLAUDE_DIR = os.path.expanduser("~/.claude")
USAGE_FILE = os.path.join(CLAUDE_DIR, "token_usage.json")
SESSION_FILE = os.path.join(CLAUDE_DIR, "token_current_session")

RESET = "\033[0m"
GREEN = "\033[32m"
CYAN  = "\033[36m"
DIM   = "\033[2m"
BOLD  = "\033[1m"

def _fmt(n):
    if n >= 1_000_000:
        return "{:.1f}M".format(n / 1_000_000)
    if n >= 1_000:
        return "{:.0f}k".format(n / 1_000)
    return str(n)

def main():
    try:
        with open(USAGE_FILE) as f:
            data = json.load(f)
    except Exception:
        sys.exit(0)

    total = data.get("total", {})
    sessions = data.get("sessions", {})

    # Try to get current session
    sess = None
    try:
        with open(SESSION_FILE) as f:
            sid = f.read().strip()
        if sid and sid in sessions:
            sess = sessions[sid]
    except Exception:
        pass

    # Format: show session cost + total cost + calls
    parts = []

    if sess:
        sess_cost   = sess.get("cost_usd", 0)
        sess_calls  = sess.get("calls", 0)
        sess_in     = sess.get("input_tokens", 0)
        sess_out    = sess.get("output_tokens", 0)
        sess_cache  = sess.get("cache_read_tokens", 0)
        parts.append(
            "{}{} session: ${:.4f} · {}↑ {}↓ {}⚡ · {} calls{}".format(
                BOLD, GREEN, sess_cost,
                _fmt(sess_in), _fmt(sess_out), _fmt(sess_cache),
                sess_calls, RESET
            )
        )

    total_cost  = total.get("cost_usd", 0)
    total_calls = total.get("calls", 0)
    total_in    = total.get("input_tokens", 0)
    total_out   = total.get("output_tokens", 0)
    total_cache = total.get("cache_read_tokens", 0)
    parts.append(
        "{}total: ${:.4f} · {}↑ {}↓ {}⚡ · {} calls{}".format(
            DIM, total_cost,
            _fmt(total_in), _fmt(total_out), _fmt(total_cache),
            total_calls, RESET
        )
    )

    if parts:
        sys.stdout.write(" · ".join(parts))

if __name__ == "__main__":
    main()
