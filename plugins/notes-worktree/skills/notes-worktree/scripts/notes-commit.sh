#!/bin/bash
# Quick commit helper for notes branch
# Usage: notes-commit.sh [message]

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
