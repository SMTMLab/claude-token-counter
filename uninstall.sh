#!/usr/bin/env bash
# uninstall.sh — Remove claude-token-counter hooks from Claude Code
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[info]${NC}  $*"; }
success() { echo -e "${GREEN}[ok]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }

HOOKS_DIR="${HOME}/.claude/hooks"
SETTINGS_FILE="${HOME}/.claude/settings.json"
USAGE_FILE="${HOME}/.claude/token_usage.json"

remove_hook_files() {
    local removed=0
    for f in token_counter.py token_session_init.py token_statusline.py; do
        if [[ -f "${HOOKS_DIR}/${f}" ]]; then
            rm -f "${HOOKS_DIR}/${f}"
            success "Removed ${HOOKS_DIR}/${f}"
            removed=1
        fi
    done
    [[ $removed -eq 0 ]] && warn "No hook files found — skipping."
}

remove_settings_entries() {
    if [[ ! -f "${SETTINGS_FILE}" ]]; then
        warn "${SETTINGS_FILE} not found — nothing to clean up."
        return
    fi

    info "Cleaning up ${SETTINGS_FILE} …"

    python3 - <<'PYEOF'
import json, os, sys

settings_file = os.path.expanduser("~/.claude/settings.json")

try:
    with open(settings_file, "r") as f:
        settings = json.load(f)
except Exception as e:
    print("[warn]  Could not parse {}: {}".format(settings_file, e))
    sys.exit(0)

MARKERS = ("token_counter.py", "token_session_init.py", "token_statusline.py")

def is_ours(command):
    return any(m in command for m in MARKERS)

changes = []

# Remove hook entries from Stop, UserPromptSubmit, SessionStart
for event in ("Stop", "UserPromptSubmit", "SessionStart"):
    entries = settings.get("hooks", {}).get(event, [])
    new_entries = []
    for entry in entries:
        filtered = [h for h in entry.get("hooks", []) if not is_ours(h.get("command", ""))]
        if filtered:
            new_entry = dict(entry)
            new_entry["hooks"] = filtered
            new_entries.append(new_entry)
        else:
            changes.append("removed {} entry".format(event))
    if event in settings.get("hooks", {}):
        if new_entries:
            settings["hooks"][event] = new_entries
        else:
            del settings["hooks"][event]

# Clean up empty hooks
if "hooks" in settings and not settings["hooks"]:
    del settings["hooks"]

# Remove statusLine
if is_ours(settings.get("statusLine", {}).get("command", "")):
    del settings["statusLine"]
    changes.append("removed statusLine")

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)

if changes:
    for c in changes:
        print("[ok]    {}".format(c))
else:
    print("[ok]    No entries found — nothing to remove.")

PYEOF
}

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

main() {
    echo -e "\n${BOLD}claude-token-counter — uninstaller${NC}\n"

    remove_hook_files
    remove_settings_entries
    prompt_keep_usage_data

    echo ""
    echo -e "${BOLD}Uninstall complete.${NC}"
}

main "$@"
