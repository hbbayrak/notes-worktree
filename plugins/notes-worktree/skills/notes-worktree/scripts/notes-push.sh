#!/bin/bash
# Push notes branch to remote
# Usage: notes-push.sh [remote]

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
REMOTE="${1:-origin}"

if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "Usage: notes-push.sh [REMOTE]"
    echo ""
    echo "Push notes branch to remote repository."
    echo ""
    echo "Arguments:"
    echo "  REMOTE    Remote name (default: 'origin')"
    echo ""
    echo "Examples:"
    echo "  ./notes-push.sh            # Push to origin"
    echo "  ./notes-push.sh upstream   # Push to upstream"
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
# Push
# -------------------------------------------
cd "$NOTES_ROOT"

BRANCH=$(git branch --show-current)

echo ""
print_info "Pushing notes branch '$BRANCH' to $REMOTE..."
echo ""

# Check if upstream is set
UPSTREAM=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")

if [ -z "$UPSTREAM" ]; then
    # No upstream set, push with -u
    print_info "Setting upstream to $REMOTE/$BRANCH"
    git push -u "$REMOTE" "$BRANCH"
else
    git push
fi

print_success "Push complete!"
echo ""
