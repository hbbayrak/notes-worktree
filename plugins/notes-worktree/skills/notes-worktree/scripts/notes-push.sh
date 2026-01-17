#!/bin/bash
# Push notes branch to remote
# Usage: notes-push.sh [remote]

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
