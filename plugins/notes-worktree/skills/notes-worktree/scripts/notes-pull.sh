#!/bin/bash
# Pull notes branch from remote and sync symlinks
# Usage: notes-pull.sh [remote]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_info() { echo -e "${BLUE}$1${NC}"; }

# -------------------------------------------
# Parse arguments
# -------------------------------------------
REMOTE="${1:-origin}"
SYNC_AFTER=true

if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "Usage: notes-pull.sh [REMOTE]"
    echo ""
    echo "Pull notes branch from remote and run sync to update symlinks."
    echo ""
    echo "Arguments:"
    echo "  REMOTE    Remote name (default: 'origin')"
    echo ""
    echo "Examples:"
    echo "  ./notes-pull.sh            # Pull from origin"
    echo "  ./notes-pull.sh upstream   # Pull from upstream"
    exit 0
fi

if [[ "$1" == "--no-sync" ]]; then
    SYNC_AFTER=false
    REMOTE="${2:-origin}"
fi

# -------------------------------------------
# Resolve paths
# -------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$SCRIPT_DIR" == */notes/scripts ]] || [[ "$SCRIPT_DIR" == */*/scripts ]]; then
    NOTES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    PROJECT_ROOT="$(cd "$NOTES_ROOT/.." && pwd)"
else
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    NOTES_ROOT="$PROJECT_ROOT/notes"
fi

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
if [ -n "$(git status --porcelain)" ]; then
    print_warning "Local changes detected in notes branch"
    git status --short
    echo ""
    read -p "Stash changes before pull? [Y/n]: " stash_choice
    stash_choice="${stash_choice:-y}"
    if [[ "$stash_choice" =~ ^[Yy]$ ]]; then
        git stash push -m "Auto-stash before notes-pull"
        STASHED=true
    fi
fi

# Pull
git pull "$REMOTE" "$BRANCH"

# Pop stash if we stashed
if [ "${STASHED:-false}" = true ]; then
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
    "$SCRIPT_DIR/sync-notes.sh" --cleanup --quiet
    print_success "Symlinks updated!"
    echo ""
fi
