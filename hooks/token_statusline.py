#!/usr/bin/env python3
import json, os, sys



CLAUDE_DIR = os.path.expanduser("~/.claude")
USAGE_FILE = os.path.join(CLAUDE_DIR, "token_usage.json")

RESET  = "\033[0m"
GREEN  = "\033[32m"
YELLOW = "\033[33m"
RED    = "\033[31m"
CYAN   = "\033[36m"
DIM    = "\033[2m"
BOLD   = "\033[1m"

CONTEXT_WINDOWS = {
    "claude-opus-4":   200_000,
    "claude-sonnet-4": 200_000,
    "claude-haiku-4":  200_000,
    "claude-opus-3":   200_000,
    "claude-sonnet-3": 200_000,
    "claude-haiku-3":  200_000,
}
DEFAULT_CONTEXT = 200_000


def _context_window(model):
    for prefix in sorted(CONTEXT_WINDOWS.keys(), key=len, reverse=True):
        if model.startswith(prefix):
            return CONTEXT_WINDOWS[prefix]
    return DEFAULT_CONTEXT

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

    sess = None
    if sessions:
        ppid = sys.argv[1] if len(sys.argv) > 1 else str(os.getppid())
        try:
            with open("/tmp/claude_session_{}".format(ppid)) as f:
                content = f.read().strip().split('\n', 1)
            pinned_sid = content[0]
            sess = sessions.get(pinned_sid)
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

        last_in  = sess.get("last_input_tokens", 0)
        last_cw  = sess.get("last_cache_write_tokens", 0)
        last_cr  = sess.get("last_cache_read_tokens", 0)
        model    = sess.get("model", "unknown")
        ctx_window = _context_window(model)
        ctx_used   = last_in + last_cw + last_cr
        ctx_pct    = ctx_used / ctx_window * 100

        if ctx_pct < 40:
            ctx_color = GREEN
        elif ctx_pct < 65:
            ctx_color = YELLOW
        else:
            ctx_color = RED

        ctx_str = "{}{:.0f}% ctx{}".format(ctx_color, ctx_pct, RESET)
        if ctx_pct >= 65:
            ctx_str += " {}⚠ /save{}".format(RED + BOLD, RESET)

        parts.append(
            "{}{} session: ${:.4f} · {}↑ {}↓ {}⚡ · {} calls · {}{}".format(
                BOLD, GREEN, sess_cost,
                _fmt(sess_in), _fmt(sess_out), _fmt(sess_cache),
                sess_calls, ctx_str, RESET
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
