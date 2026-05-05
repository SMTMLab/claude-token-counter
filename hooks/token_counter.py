#!/usr/bin/env python3
"""
Claude Code Stop hook — tracks token usage and costs per session and total.
Registered in ~/.claude/settings.json under hooks.Stop.
"""

import json
import os
import sys
import datetime

# ---------------------------------------------------------------------------
# Pricing table: USD per million tokens
# Keys are model prefixes; matched longest-first.
# ---------------------------------------------------------------------------
PRICING = {
    "claude-opus-4":   {"input": 15.00, "output": 75.00, "cache_write": 18.75, "cache_read": 1.50},
    "claude-sonnet-4": {"input":  3.00, "output": 15.00, "cache_write":  3.75, "cache_read": 0.30},
    "claude-haiku-4":  {"input":  0.80, "output":  4.00, "cache_write":  1.00, "cache_read": 0.08},
    "claude-opus-3":   {"input": 15.00, "output": 75.00, "cache_write": 18.75, "cache_read": 1.50},
    "claude-sonnet-3": {"input":  3.00, "output": 15.00, "cache_write":  3.75, "cache_read": 0.30},
    "claude-haiku-3":  {"input":  0.25, "output":  1.25, "cache_write":  0.30, "cache_read": 0.03},
}

# Paths
CLAUDE_DIR   = os.path.expanduser("~/.claude")
USAGE_FILE   = os.path.join(CLAUDE_DIR, "token_usage.json")
ERROR_LOG    = os.path.join(CLAUDE_DIR, "token_usage_errors.log")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _now_iso():
    return datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def _log_error(message):
    try:
        os.makedirs(CLAUDE_DIR, exist_ok=True)
        with open(ERROR_LOG, "a") as f:
            f.write("[{}] {}\n".format(_now_iso(), message))
    except Exception:
        pass


def _get_pricing(model):
    """
    Return the pricing dict for *model* or None if unknown.
    Matches by longest prefix first.
    """
    for prefix in sorted(PRICING.keys(), key=len, reverse=True):
        if model.startswith(prefix):
            return PRICING[prefix]
    return None


def _calculate_cost(pricing, input_tokens, output_tokens, cache_write, cache_read):
    """Return cost in USD (float) given token counts and a pricing dict."""
    per_m = 1_000_000.0
    cost = (
        input_tokens    * pricing["input"]       / per_m +
        output_tokens   * pricing["output"]      / per_m +
        cache_write     * pricing["cache_write"]  / per_m +
        cache_read      * pricing["cache_read"]   / per_m
    )
    return cost


# ---------------------------------------------------------------------------
# File I/O with locking
# ---------------------------------------------------------------------------

def _empty_usage():
    return {
        "total": {
            "input_tokens":       0,
            "output_tokens":      0,
            "cache_write_tokens": 0,
            "cache_read_tokens":  0,
            "cost_usd":           0.0,
            "calls":              0,
        },
        "sessions": {},
    }


def _load_usage():
    """Load token_usage.json; return a fresh structure if missing or corrupt."""
    if not os.path.exists(USAGE_FILE):
        return _empty_usage()
    try:
        with open(USAGE_FILE, "r") as f:
            data = json.load(f)
        # Basic sanity: must have 'total' and 'sessions'
        if "total" not in data or "sessions" not in data:
            raise ValueError("missing keys")
        return data
    except Exception as e:
        # Backup and start fresh
        bak = USAGE_FILE + ".bak"
        try:
            import shutil
            shutil.copy2(USAGE_FILE, bak)
        except Exception:
            pass
        _log_error("Corrupted token_usage.json (backed up to .bak): {}".format(e))
        return _empty_usage()


def _save_usage(data):
    """Write token_usage.json with advisory file locking."""
    os.makedirs(CLAUDE_DIR, exist_ok=True)
    try:
        with open(USAGE_FILE, "w") as f:
            import fcntl
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                json.dump(data, f, indent=2)
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    except PermissionError as e:
        _log_error("Warning: could not save token usage (permission denied): {}".format(e))


# ---------------------------------------------------------------------------
# Core logic
# ---------------------------------------------------------------------------

def _extract_from_transcript(transcript_path):
    """
    Read the JSONL transcript and return (model, usage) from the last
    assistant entry.  Returns ("unknown", {}) on any failure.
    Retries up to 5 times with 200ms delay — Stop fires before Claude Code
    finishes writing the response to the JSONL.
    """
    import time
    for attempt in range(5):
        try:
            with open(transcript_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
        except Exception as e:
            _log_error("Could not read transcript {}: {}".format(transcript_path, e))
            return "unknown", {}

        last_entry = None
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except Exception:
                continue
            if entry.get("type") == "assistant" and not entry.get("isMeta"):
                last_entry = entry

        if last_entry is not None:
            break
        time.sleep(0.2)

    if last_entry is None:
        _log_error("No assistant entry found in transcript: {}".format(transcript_path))
        return "unknown", {}

    try:
        message = last_entry["message"]
        model   = message.get("model", "unknown")
        usage   = message.get("usage") or {}
        return model, usage
    except (KeyError, TypeError) as e:
        _log_error("Malformed assistant entry in transcript {}: {}".format(transcript_path, e))
        return "unknown", {}




def process(event):
    session_id      = event.get("session_id", "unknown")
    transcript_path = event.get("transcript_path", "")

    if transcript_path:
        model, usage = _extract_from_transcript(transcript_path)
    else:
        _log_error("No transcript_path in event; falling back to zero counts.")
        model, usage = "unknown", {}

    input_tokens   = int(usage.get("input_tokens", 0))
    output_tokens  = int(usage.get("output_tokens", 0))
    cache_write    = int(usage.get("cache_creation_input_tokens", 0))
    cache_read     = int(usage.get("cache_read_input_tokens", 0))

    pricing    = _get_pricing(model)
    if pricing is not None:
        call_cost = _calculate_cost(pricing, input_tokens, output_tokens, cache_write, cache_read)
    else:
        call_cost = None

    # --- Load and update storage ---
    data = _load_usage()
    now  = _now_iso()

    # Session entry
    sessions = data["sessions"]
    if session_id not in sessions:
        sessions[session_id] = {
            "started_at":         now,
            "last_updated":       now,
            "model":              model,
            "input_tokens":       0,
            "output_tokens":      0,
            "cache_write_tokens": 0,
            "cache_read_tokens":  0,
            "cost_usd":           0.0,
            "calls":              0,
            "last_input_tokens":       0,
            "last_cache_write_tokens": 0,
            "last_cache_read_tokens":  0,
        }

    sess = sessions[session_id]
    sess["last_updated"]       = now
    sess["model"]              = model
    sess["input_tokens"]       += input_tokens
    sess["output_tokens"]      += output_tokens
    sess["cache_write_tokens"] += cache_write
    sess["cache_read_tokens"]  += cache_read
    sess["calls"]              += 1
    sess["last_input_tokens"]       = input_tokens
    sess["last_cache_write_tokens"] = cache_write
    sess["last_cache_read_tokens"]  = cache_read
    if call_cost is not None:
        sess["cost_usd"] = round(sess["cost_usd"] + call_cost, 8)

    # Totals
    total = data["total"]
    total["input_tokens"]       += input_tokens
    total["output_tokens"]      += output_tokens
    total["cache_write_tokens"] += cache_write
    total["cache_read_tokens"]  += cache_read
    total["calls"]              += 1
    if call_cost is not None:
        total["cost_usd"] = round(total["cost_usd"] + call_cost, 8)

    _save_usage(data)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    try:
        raw = sys.stdin.read()
        event = json.loads(raw)
    except Exception as e:
        _log_error("Malformed JSON from stdin: {} | raw: {!r}".format(e, locals().get("raw", "")))
        sys.exit(0)

    try:
        process(event)
    except Exception as e:
        _log_error("Unexpected error in process(): {}".format(e))

    sys.exit(0)


if __name__ == "__main__":
    main()
