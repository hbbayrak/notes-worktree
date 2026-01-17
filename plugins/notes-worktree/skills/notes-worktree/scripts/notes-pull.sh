#!/bin/bash
# Pull notes branch from remote and sync symlinks
# Usage: notes-pull.sh [OPTIONS] [REMOTE]

set -e

# Source common utilities (resolve symlinks)
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# -------------------------------------------
# Parse arguments
# -------------------------------------------
REMOTE="origin"
SYNC_AFTER=true
AUTO_STASH=false

show_help() {
    echo "Usage: notes-pull.sh [OPTIONS] [REMOTE]"
    echo ""
    echo "Pull notes branch from remote and run sync to update symlinks."
    echo ""
    echo "Arguments:"
    echo "  REMOTE           Remote name (default: 'origin')"
    echo ""
    echo "Options:"
    echo "  --auto-stash     Automatically stash local changes before pull"
    echo "  --no-sync        Skip running sync after pull"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./notes-pull.sh                    # Pull from origin"
    echo "  ./notes-pull.sh upstream           # Pull from upstream"
    echo "  ./notes-pull.sh --auto-stash       # Auto-stash any local changes"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-stash)
            AUTO_STASH=true
            shift
            ;;
        --no-sync)
            SYNC_AFTER=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            REMOTE="$1"
            shift
            ;;
    esac
done

# -------------------------------------------
# Resolve paths and load configuration
# -------------------------------------------
init_project_root
load_notes_config

# Verify notes exists
if [ ! -d "$NOTES_ROOT" ]; then
    print_error "Notes directory not found at $NOTES_ROOT"
    exit 1
fi

# -------------------------------------------
# Pull
# -------------------------------------------
cd "$NOTES_ROOT"

BRANCH=$(git branch --show-current)

echo ""
print_info "Pulling notes branch '$BRANCH' from $REMOTE..."
echo ""

# Check for local changes
STASHED=false
if [ -n "$(git status --porcelain)" ]; then
    if $AUTO_STASH; then
        print_warning "Local changes detected, auto-stashing..."
        git stash push -m "Auto-stash before notes-pull"
        STASHED=true
    else
        print_error "Local changes detected in notes branch."
        git status --short
        echo ""
        echo "Use --auto-stash to automatically stash changes, or commit manually."
        exit 1
    fi
fi

# Pull
git pull "$REMOTE" "$BRANCH"

# Pop stash if we stashed
if $STASHED; then
    echo ""
    print_info "Restoring stashed changes..."
    git stash pop || print_warning "Stash pop failed - check 'git stash list'"
fi

print_success "Pull complete!"
echo ""

# -------------------------------------------
# Sync symlinks
# -------------------------------------------
if $SYNC_AFTER; then
    cd "$PROJECT_ROOT"
    print_info "Running sync to update symlinks..."
    echo ""
    "$PROJECT_ROOT/scripts/sync-notes.sh" --cleanup --quiet
    print_success "Symlinks updated!"
    echo ""
fi
