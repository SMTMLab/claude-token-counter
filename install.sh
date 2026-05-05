#!/usr/bin/env bash
# install.sh — Install the claude-token-counter hooks into Claude Code
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
HOOKS_DIR="${HOME}/.claude/hooks"
SETTINGS_FILE="${HOME}/.claude/settings.json"

install_hook_files() {
    mkdir -p "${HOOKS_DIR}"

    cp "${SCRIPT_DIR}/hooks/token_counter.py"      "${HOOKS_DIR}/token_counter.py"
    chmod +x "${HOOKS_DIR}/token_counter.py"
    success "Copied token_counter.py"

    cp "${SCRIPT_DIR}/hooks/token_session_init.py" "${HOOKS_DIR}/token_session_init.py"
    chmod +x "${HOOKS_DIR}/token_session_init.py"
    success "Copied token_session_init.py"

    cp "${SCRIPT_DIR}/hooks/token_statusline.py"   "${HOOKS_DIR}/token_statusline.py"
    chmod +x "${HOOKS_DIR}/token_statusline.py"
    success "Copied token_statusline.py"
}

merge_settings() {
    info "Merging hooks and statusLine into ${SETTINGS_FILE} …"

    python3 - <<'PYEOF'
import json, os, sys

settings_file = os.path.expanduser("~/.claude/settings.json")

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

if "hooks" not in settings:
    settings["hooks"] = {}

def ensure_hook(settings, event, command, marker):
    """Add command to hooks[event] if not already present (detected by marker string)."""
    hooks_list = settings["hooks"].setdefault(event, [])
    for entry in hooks_list:
        for h in entry.get("hooks", []):
            if marker in h.get("command", ""):
                return False  # already registered
    hooks_list.append({"matcher": "", "hooks": [{"type": "command", "command": command}]})
    return True

changes = []

if ensure_hook(settings, "Stop",            "python3 ~/.claude/hooks/token_counter.py $PPID",      "token_counter.py"):
    changes.append("Stop → token_counter.py")

if ensure_hook(settings, "UserPromptSubmit","python3 ~/.claude/hooks/token_session_init.py $PPID", "token_session_init.py"):
    changes.append("UserPromptSubmit → token_session_init.py")

if ensure_hook(settings, "SessionStart",    "python3 ~/.claude/hooks/token_session_init.py $PPID", "token_session_init.py"):
    changes.append("SessionStart → token_session_init.py")

# statusLine
new_statusline = {"type": "command", "command": "python3 ~/.claude/hooks/token_statusline.py $PPID"}
existing_cmd = settings.get("statusLine", {}).get("command", "")
if "token_statusline.py" not in existing_cmd:
    settings["statusLine"] = new_statusline
    changes.append("statusLine → token_statusline.py")

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)

if changes:
    for c in changes:
        print("[ok]    Registered: {}".format(c))
else:
    print("[ok]    All hooks already registered — nothing changed.")

PYEOF
}

# ---------------------------------------------------------------------------
# Smoke test
# ---------------------------------------------------------------------------
run_smoke_test() {
    info "Running smoke test …"
    local mock_json='{"session_id":"install-test","transcript_path":""}'
    if echo "$mock_json" | python3 "${HOOKS_DIR}/token_session_init.py" 2>/dev/null; then
        success "Smoke test passed (token_session_init)"
    else
        warn "Smoke test failed — check ${HOME}/.claude/token_usage_errors.log"
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
    install_hook_files
    merge_settings
    run_smoke_test

    echo ""
    echo -e "${BOLD}Installation complete.${NC}"
    echo ""
    echo "  Hooks dir  : ${HOOKS_DIR}"
    echo "  Settings   : ${SETTINGS_FILE}"
    echo "  Usage data : ${HOME}/.claude/token_usage.json"
    echo "  Error log  : ${HOME}/.claude/token_usage_errors.log"
    echo ""
    echo "Restart Claude Code for the hooks to take effect."
}

main "$@"
