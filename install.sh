#!/usr/bin/env bash
# install.sh — Install the claude-token-counter Stop hook into Claude Code
set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[info]${NC}  $*"; }
success() { echo -e "${GREEN}[ok]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
error()   { echo -e "${RED}[error]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
detect_platform() {
    local uname_s
    uname_s="$(uname -s 2>/dev/null || echo "unknown")"

    case "${OSTYPE:-}" in
        msys|cygwin)
            die "Windows Git Bash is not supported. Please use WSL or a native Linux/macOS environment."
            ;;
    esac

    case "$uname_s" in
        Darwin)
            PLATFORM="macOS"
            ;;
        Linux)
            local uname_r
            uname_r="$(uname -r 2>/dev/null || echo "")"
            if echo "$uname_r" | grep -qi "microsoft"; then
                PLATFORM="WSL"
            else
                PLATFORM="Linux"
            fi
            ;;
        *)
            die "Unsupported platform: $uname_s"
            ;;
    esac

    info "Platform detected: ${BOLD}${PLATFORM}${NC}"
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
check_python3() {
    if ! command -v python3 &>/dev/null; then
        die "python3 is not available. Please install Python 3.6 or later."
    fi
    local ver
    ver="$(python3 -c 'import sys; print("{}.{}".format(*sys.version_info[:2]))')"
    success "python3 found (version ${ver})"
}

check_claude_dir() {
    if [[ ! -d "${HOME}/.claude" ]]; then
        die "~/.claude directory not found. Is Claude Code CLI installed? Run 'claude' at least once to initialize it."
    fi
    success "~/.claude directory exists"
}

# ---------------------------------------------------------------------------
# Install steps
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="${SCRIPT_DIR}/hooks/token_counter.py"
HOOK_DST="${HOME}/.claude/hooks/token_counter.py"
STATUSLINE_SRC="${SCRIPT_DIR}/hooks/token_statusline.py"
STATUSLINE_DST="${HOME}/.claude/hooks/token_statusline.py"
SETTINGS_FILE="${HOME}/.claude/settings.json"

install_hook_file() {
    mkdir -p "${HOME}/.claude/hooks"
    cp "${HOOK_SRC}" "${HOOK_DST}"
    chmod +x "${HOOK_DST}"
    success "Copied hook to ${HOOK_DST}"
    cp "${STATUSLINE_SRC}" "${STATUSLINE_DST}"
    chmod +x "${STATUSLINE_DST}"
    success "Copied statusline script to ${STATUSLINE_DST}"
}

merge_settings() {
    info "Merging hook entry into ${SETTINGS_FILE} …"

    python3 - <<'PYEOF'
import json, os, sys

settings_file = os.path.expanduser("~/.claude/settings.json")
hook_dst = os.path.expanduser("~/.claude/hooks/token_counter.py")

new_hook = {
    "type": "command",
    "command": "python3 ~/.claude/hooks/token_counter.py"
}
new_matcher_entry = {
    "matcher": "",
    "hooks": [new_hook]
}

# Load existing settings or start fresh
if os.path.exists(settings_file):
    try:
        with open(settings_file, "r") as f:
            settings = json.load(f)
    except Exception as e:
        print("[warn]  Could not parse {}: {}. Creating backup and continuing.".format(settings_file, e))
        import shutil
        shutil.copy2(settings_file, settings_file + ".bak")
        settings = {}
else:
    settings = {}

# Navigate to hooks.Stop
if "hooks" not in settings:
    settings["hooks"] = {}
if "Stop" not in settings["hooks"]:
    settings["hooks"]["Stop"] = []

stop_hooks = settings["hooks"]["Stop"]

# Check if our command already registered anywhere in Stop
already_registered = False
for matcher_entry in stop_hooks:
    for h in matcher_entry.get("hooks", []):
        if h.get("type") == "command" and "token_counter.py" in h.get("command", ""):
            already_registered = True
            break

if already_registered:
    print("[ok]    Hook already registered in settings.json — skipping.")
else:
    # Append our matcher entry
    stop_hooks.append(new_matcher_entry)
    with open(settings_file, "w") as f:
        json.dump(settings, f, indent=2)
    print("[ok]    Hook registered in {}".format(settings_file))

PYEOF
}

setup_statusline() {
    info "Configuring statusLine in ${SETTINGS_FILE} …"

    python3 - <<'PYEOF'
import json, os

settings_file = os.path.expanduser("~/.claude/settings.json")

new_statusline = {
    "type": "command",
    "command": "python3 ~/.claude/hooks/token_statusline.py"
}

# Load existing settings or start fresh
if os.path.exists(settings_file):
    try:
        with open(settings_file, "r") as f:
            settings = json.load(f)
    except Exception as e:
        print("[warn]  Could not parse {}: {}. Skipping statusLine setup.".format(settings_file, e))
        raise SystemExit(0)
else:
    settings = {}

existing = settings.get("statusLine", {})
if existing.get("command", "") == new_statusline["command"]:
    print("[ok]    statusLine already configured — skipping.")
else:
    settings["statusLine"] = new_statusline
    with open(settings_file, "w") as f:
        json.dump(settings, f, indent=2)
    print("[ok]    statusLine configured in {}".format(settings_file))

PYEOF
}

# ---------------------------------------------------------------------------
# Smoke test
# ---------------------------------------------------------------------------
run_smoke_test() {
    info "Running smoke test …"
    local mock_json='{"session_id":"install-test","model":"claude-sonnet-4-5","usage":{"input_tokens":1200,"output_tokens":340,"cache_creation_input_tokens":0,"cache_read_input_tokens":800}}'
    if echo "$mock_json" | python3 "${HOOK_DST}"; then
        success "Smoke test passed"
    else
        warn "Smoke test exited with non-zero status — check ${HOME}/.claude/token_usage_errors.log"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo -e "\n${BOLD}claude-token-counter — installer${NC}\n"

    detect_platform
    check_python3
    check_claude_dir
    install_hook_file
    merge_settings
    setup_statusline
    run_smoke_test

    echo ""
    echo -e "${BOLD}Installation complete.${NC}"
    echo ""
    echo "  Hook script : ${HOOK_DST}"
    echo "  Statusline  : ${STATUSLINE_DST}"
    echo "  Settings    : ${SETTINGS_FILE}"
    echo "  Usage data  : ${HOME}/.claude/token_usage.json"
    echo "  Error log   : ${HOME}/.claude/token_usage_errors.log"
    echo ""
    echo "The hook will run automatically after every Claude Code session stop."
    echo "The statusline will appear in Claude Code's status bar after restart."
}

main "$@"
