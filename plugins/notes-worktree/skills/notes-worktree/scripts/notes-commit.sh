#!/bin/bash
# Quick commit helper for notes branch
# Usage: notes-commit.sh [message]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_info() { echo -e "${BLUE}$1${NC}"; }

# -------------------------------------------
# Parse arguments
# -------------------------------------------
MESSAGE="${1:-Update documentation}"

if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "Usage: notes-commit.sh [MESSAGE]"
    echo ""
    echo "Stage all changes in notes branch and commit."
    echo ""
    echo "Arguments:"
    echo "  MESSAGE    Commit message (default: 'Update documentation')"
    echo ""
    echo "Examples:"
    echo "  ./notes-commit.sh                           # Default message"
    echo "  ./notes-commit.sh 'Add API documentation'   # Custom message"
    exit 0
fi

# -------------------------------------------
# Resolve paths (symlink-safe using git)
# -------------------------------------------
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$PROJECT_ROOT" ]; then
    print_error "Not a git repository."
    exit 1
fi

# Load configuration
CONFIG_FILE="$PROJECT_ROOT/notes/.notesrc"
if [ -f "$CONFIG_FILE" ]; then
    WORKTREE_DIR=$(grep -o '"worktree"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    WORKTREE_DIR="${WORKTREE_DIR#./}"
else
    WORKTREE_DIR="notes"
fi

NOTES_ROOT="$PROJECT_ROOT/$WORKTREE_DIR"

# Verify notes exists
if [ ! -d "$NOTES_ROOT" ]; then
    print_error "Notes directory not found at $NOTES_ROOT"
    exit 1
fi

# -------------------------------------------
# Commit
# -------------------------------------------
cd "$NOTES_ROOT"

# Check if there are any changes
if [ -z "$(git status --porcelain)" ]; then
    print_info "No changes to commit in notes branch"
    exit 0
fi

# Stage all changes
git add -A

# Show what we're committing
echo ""
print_info "Changes to commit:"
git status --short
echo ""

# Commit
git commit -m "$MESSAGE"

print_success "Committed to notes branch: $MESSAGE"
echo ""

# Check for unpushed commits
UPSTREAM=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")
if [ -n "$UPSTREAM" ]; then
    UNPUSHED=$(git rev-list "$UPSTREAM..HEAD" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$UNPUSHED" -gt 0 ]; then
        echo "You have $UNPUSHED unpushed commit(s)."
        echo "Run: ./scripts/notes-push.sh"
    fi
else
    echo "Branch not tracking remote."
    echo "Run: ./scripts/notes-push.sh to push"
fi
echo ""
