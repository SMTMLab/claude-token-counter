#!/usr/bin/env bash
# uninstall.sh — Remove the claude-token-counter Stop hook from Claude Code
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

HOOK_DST="${HOME}/.claude/hooks/token_counter.py"
SETTINGS_FILE="${HOME}/.claude/settings.json"
USAGE_FILE="${HOME}/.claude/token_usage.json"

# ---------------------------------------------------------------------------
# Remove hook script
# ---------------------------------------------------------------------------
remove_hook_file() {
    if [[ -f "${HOOK_DST}" ]]; then
        rm -f "${HOOK_DST}"
        success "Removed ${HOOK_DST}"
    else
        warn "Hook file not found at ${HOOK_DST} — skipping."
    fi
}

# ---------------------------------------------------------------------------
# Remove hook entry from settings.json (preserve all other hooks and keys)
# ---------------------------------------------------------------------------
remove_settings_entry() {
    if [[ ! -f "${SETTINGS_FILE}" ]]; then
        warn "${SETTINGS_FILE} not found — nothing to clean up."
        return
    fi

    info "Removing token_counter entry from ${SETTINGS_FILE} …"

    python3 - <<'PYEOF'
import json, os, sys

settings_file = os.path.expanduser("~/.claude/settings.json")

try:
    with open(settings_file, "r") as f:
        settings = json.load(f)
except Exception as e:
    print("[warn]  Could not parse {}: {}".format(settings_file, e))
    sys.exit(0)

stop_hooks = settings.get("hooks", {}).get("Stop", [])
if not stop_hooks:
    print("[ok]    No Stop hooks found — nothing to remove.")
    sys.exit(0)

original_len = len(stop_hooks)
new_stop_hooks = []

for matcher_entry in stop_hooks:
    filtered_hooks = [
        h for h in matcher_entry.get("hooks", [])
        if not ("token_counter.py" in h.get("command", ""))
    ]
    if filtered_hooks:
        # Keep this matcher entry but without our hook
        new_entry = dict(matcher_entry)
        new_entry["hooks"] = filtered_hooks
        new_stop_hooks.append(new_entry)
    # If filtered_hooks is empty, drop the entire matcher entry

settings["hooks"]["Stop"] = new_stop_hooks

# Clean up empty hooks dict
if not settings["hooks"]["Stop"]:
    del settings["hooks"]["Stop"]
if not settings["hooks"]:
    del settings["hooks"]

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)

removed = original_len - len(new_stop_hooks)
if removed > 0:
    print("[ok]    Removed token_counter hook entry from {}".format(settings_file))
else:
    print("[ok]    No token_counter hook entry found — nothing to remove.")

PYEOF
}

# ---------------------------------------------------------------------------
# Optionally remove usage data
# ---------------------------------------------------------------------------
prompt_keep_usage_data() {
    if [[ ! -f "${USAGE_FILE}" ]]; then
        return
    fi

    echo ""
    echo -e "${YELLOW}Keep historical token usage data?${NC}"
    echo "  File: ${USAGE_FILE}"
    echo -n "  Keep it? [Y/n] "
    read -r answer

    case "${answer}" in
        [nN][oO]|[nN])
            rm -f "${USAGE_FILE}"
            success "Removed ${USAGE_FILE}"
            ;;
        *)
            info "Keeping ${USAGE_FILE}"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo -e "\n${BOLD}claude-token-counter — uninstaller${NC}\n"

    remove_hook_file
    remove_settings_entry
    prompt_keep_usage_data

    echo ""
    echo -e "${BOLD}Uninstall complete.${NC}"
    echo ""
    echo "The token counter hook has been removed from Claude Code."
    echo "Your other hooks and settings were preserved."
}

main "$@"
