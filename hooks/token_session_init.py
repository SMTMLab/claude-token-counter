#!/usr/bin/env python3
import json
import os
import sys
import datetime

CLAUDE_DIR    = os.path.expanduser("~/.claude")
USAGE_FILE    = os.path.join(CLAUDE_DIR, "token_usage.json")
ERROR_LOG     = os.path.join(CLAUDE_DIR, "token_usage_errors.log")


def _now_iso():
    return datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def _log_error(message):
    try:
        os.makedirs(CLAUDE_DIR, exist_ok=True)
        with open(ERROR_LOG, "a") as f:
            f.write("[{}] {}\n".format(_now_iso(), message))
    except Exception:
        pass


def _load_usage():
    if not os.path.exists(USAGE_FILE):
        return {"total": {"input_tokens": 0, "output_tokens": 0, "cache_write_tokens": 0, "cache_read_tokens": 0, "cost_usd": 0.0, "calls": 0}, "sessions": {}}
    try:
        with open(USAGE_FILE, "r") as f:
            data = json.load(f)
        if "total" not in data or "sessions" not in data:
            raise ValueError("missing keys")
        return data
    except Exception:
        return {"total": {"input_tokens": 0, "output_tokens": 0, "cache_write_tokens": 0, "cache_read_tokens": 0, "cost_usd": 0.0, "calls": 0}, "sessions": {}}


def _save_usage(data):
    os.makedirs(CLAUDE_DIR, exist_ok=True)
    try:
        with open(USAGE_FILE, "w") as f:
            import fcntl
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                json.dump(data, f, indent=2)
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    except Exception:
        pass


def _blank_session(now):
    return {
        "started_at":              now,
        "last_updated":            now,
        "model":                   "unknown",
        "input_tokens":            0,
        "output_tokens":           0,
        "cache_write_tokens":      0,
        "cache_read_tokens":       0,
        "cost_usd":                0.0,
        "calls":                   0,
        "last_input_tokens":       0,
        "last_cache_write_tokens": 0,
        "last_cache_read_tokens":  0,
    }


def process(event):
    session_id      = event.get("session_id", "")
    transcript_path = event.get("transcript_path", "")
    source          = event.get("source", "")

    if not session_id:
        return

    ppid = sys.argv[1] if len(sys.argv) > 1 else str(os.getppid())
    try:
        with open("/tmp/claude_session_{}".format(ppid), "w") as f:
            f.write("{}\n{}".format(session_id, transcript_path))
    except Exception:
        pass

    data     = _load_usage()
    sessions = data.get("sessions", {})
    now      = _now_iso()

    is_new_session = session_id not in sessions
    is_cleared     = source == "clear"

    if not is_new_session and not is_cleared:
        return

    data["sessions"][session_id] = _blank_session(now)
    _save_usage(data)


def main():
    try:
        raw = sys.stdin.read()
        event = json.loads(raw)
    except Exception as e:
        _log_error("token_session_init: malformed JSON: {}".format(e))
        sys.exit(0)

    try:
        process(event)
    except Exception as e:
        _log_error("token_session_init: unexpected error: {}".format(e))

    sys.exit(0)


if __name__ == "__main__":
    main()
