#!/usr/bin/env bash
# ABOUTME: Installer for the team's shared Claude Code configuration.
# ABOUTME: Backs up existing ~/.claude, clones/moves repo into place,
# ABOUTME: substitutes __HOME__ placeholders, creates personal file stubs,
# ABOUTME: and installs macOS dependencies. Safe to re-run (idempotent).

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
BACKUP_DIR="$HOME/.claude-backup-$(date +%Y%m%d-%H%M%S)"
REPO_URL="REPLACE_WITH_YOUR_REPO_URL"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# --- Pre-flight checks ---
check_prerequisites() {
    info "Checking prerequisites..."

    if ! command -v git &>/dev/null; then
        fail "git is not installed. Install it first: https://git-scm.com"
    fi

    if ! command -v claude &>/dev/null; then
        warn "Claude Code CLI not found. Install it: https://docs.anthropic.com/en/docs/claude-code"
        warn "Continuing anyway — you'll need it to use this config."
    fi

    ok "Prerequisites OK"
}

# --- Backup existing config ---
backup_existing() {
    if [[ -d "$CLAUDE_DIR" ]]; then
        # Check if it's already this repo
        if [[ -d "$CLAUDE_DIR/.git" ]] && git -C "$CLAUDE_DIR" remote -v 2>/dev/null | grep -q "claude-config\|dotclaude\|\.claude"; then
            info "Existing ~/.claude appears to be this repo already. Running in update mode."
            return 0
        fi

        info "Backing up existing ~/.claude to $BACKUP_DIR"
        cp -a "$CLAUDE_DIR" "$BACKUP_DIR"
        ok "Backup created at $BACKUP_DIR"
    fi
}

# --- Clone or update repo ---
setup_repo() {
    if [[ -d "$CLAUDE_DIR/.git" ]]; then
        info "Updating existing repo..."
        git -C "$CLAUDE_DIR" pull --rebase 2>/dev/null || warn "Could not pull latest. You may need to resolve conflicts."
    else
        if [[ -d "$CLAUDE_DIR" ]]; then
            # Move existing content aside, clone, then restore personal files
            local temp_dir
            temp_dir=$(mktemp -d)
            info "Moving existing ~/.claude contents to temp..."
            mv "$CLAUDE_DIR" "$temp_dir/old-claude"

            info "Cloning repo to ~/.claude..."
            git clone "$REPO_URL" "$CLAUDE_DIR"

            # Restore personal files that shouldn't be overwritten
            for f in rules/personal.md memory/journal.md memory/lessons.md settings.local.json schedules.json; do
                if [[ -f "$temp_dir/old-claude/$f" ]]; then
                    mkdir -p "$CLAUDE_DIR/$(dirname "$f")"
                    cp "$temp_dir/old-claude/$f" "$CLAUDE_DIR/$f"
                    ok "Restored personal file: $f"
                fi
            done

            # Restore project memory dirs (per-project auto-memory)
            if [[ -d "$temp_dir/old-claude/projects" ]]; then
                cp -a "$temp_dir/old-claude/projects" "$CLAUDE_DIR/projects"
                ok "Restored projects/ (per-project memory)"
            fi

            rm -rf "$temp_dir"
        else
            info "Cloning repo to ~/.claude..."
            git clone "$REPO_URL" "$CLAUDE_DIR"
        fi
    fi

    ok "Repo ready at $CLAUDE_DIR"
}

# --- Substitute __HOME__ placeholders ---
substitute_paths() {
    info "Substituting __HOME__ placeholders with $HOME..."

    local settings="$CLAUDE_DIR/settings.json"
    if [[ -f "$settings" ]] && grep -q '__HOME__' "$settings"; then
        sed -i.bak "s|__HOME__|$HOME|g" "$settings"
        rm -f "$settings.bak"
        ok "settings.json paths updated"

        # Tell git to ignore local path changes
        git -C "$CLAUDE_DIR" update-index --assume-unchanged "$settings" 2>/dev/null || true
        ok "settings.json marked assume-unchanged (local path edits won't show in git)"
    else
        ok "settings.json already has correct paths"
    fi
}

# --- Create personal file stubs ---
create_personal_stubs() {
    info "Creating personal file stubs (won't overwrite existing)..."

    # Personal rules
    if [[ ! -f "$CLAUDE_DIR/rules/personal.md" ]]; then
        cp "$CLAUDE_DIR/rules/personal.md.example" "$CLAUDE_DIR/rules/personal.md"
        ok "Created rules/personal.md — edit this with your name and preferences"
    else
        ok "rules/personal.md already exists"
    fi

    # Memory journal
    if [[ ! -f "$CLAUDE_DIR/memory/journal.md" ]]; then
        cat > "$CLAUDE_DIR/memory/journal.md" << 'JOURNAL'
# Claude Code Session Journal

Append-only log of session activity. Searchable by date, file, tool, or error.

---
JOURNAL
        ok "Created memory/journal.md"
    else
        ok "memory/journal.md already exists"
    fi

    # Memory lessons
    if [[ ! -f "$CLAUDE_DIR/memory/lessons.md" ]]; then
        cat > "$CLAUDE_DIR/memory/lessons.md" << 'LESSONS'
# Lessons Learned

Curated patterns from journal entries. High-signal, actionable insights.

---
LESSONS
        ok "Created memory/lessons.md"
    else
        ok "memory/lessons.md already exists"
    fi
}

# --- Install macOS dependencies ---
install_deps() {
    info "Checking optional dependencies..."

    if [[ "$(uname)" == "Darwin" ]]; then
        if ! command -v terminal-notifier &>/dev/null; then
            if command -v brew &>/dev/null; then
                info "Installing terminal-notifier (macOS notifications)..."
                brew install terminal-notifier
                ok "terminal-notifier installed"
            else
                warn "terminal-notifier not found and Homebrew not available."
                warn "Notifications will be silent. Install manually: brew install terminal-notifier"
            fi
        else
            ok "terminal-notifier already installed"
        fi
    fi
}

# --- Make scripts executable ---
fix_permissions() {
    info "Ensuring scripts are executable..."
    chmod +x "$CLAUDE_DIR"/scripts/*.sh 2>/dev/null || true
    ok "Script permissions set"
}

# --- Print summary ---
print_summary() {
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Installation complete!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Next steps:"
    echo ""
    echo "  1. Edit your personal config:"
    echo -e "     ${BLUE}vim ~/.claude/rules/personal.md${NC}"
    echo "     (Set your name, add any personal preferences)"
    echo ""
    echo "  2. Start Claude Code in any project:"
    echo -e "     ${BLUE}claude${NC}"
    echo ""
    echo "  What you get:"
    echo "    - Shared team rules (code style, VIBE protocol)"
    echo "    - Skills library (PR review, debugging, testing, etc.)"
    echo "    - Git safety hooks (prevents force-push, protected file deletion)"
    echo "    - Session journaling and auto-notifications"
    echo ""

    if [[ -d "$BACKUP_DIR" ]]; then
        echo -e "  ${YELLOW}Your old ~/.claude was backed up to:${NC}"
        echo -e "  ${YELLOW}$BACKUP_DIR${NC}"
        echo ""
    fi
}

# --- Main ---
main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Claude Code Team Config Installer       ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""

    check_prerequisites
    backup_existing
    setup_repo
    substitute_paths
    create_personal_stubs
    install_deps
    fix_permissions
    print_summary
}

main "$@"
