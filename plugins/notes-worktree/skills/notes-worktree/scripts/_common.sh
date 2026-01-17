#!/bin/bash
# Common utilities for notes-worktree scripts
# Sourced by all scripts to provide:
# - Project root detection (works via symlinks)
# - Symlink resolution
# - Color/logging functions
# - Configuration loading

# -------------------------------------------
# Resolve script's actual location (handle symlinks)
# -------------------------------------------
resolve_script_dir() {
    local source="${BASH_SOURCE[1]}"  # Caller's script
    while [ -L "$source" ]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    echo "$(cd -P "$(dirname "$source")" && pwd)"
}

SCRIPT_DIR="$(resolve_script_dir)"

# -------------------------------------------
# Find project root (use git rev-parse for reliability)
# -------------------------------------------
find_project_root() {
    # Use git's own method - more reliable than walking directories
    git rev-parse --show-toplevel 2>/dev/null
}

# -------------------------------------------
# Colors for output
# -------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# -------------------------------------------
# Logging functions
# -------------------------------------------
print_error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_info() { echo -e "${BLUE}$1${NC}"; }

# Verbosity-aware logging (requires QUIET and VERBOSE variables)
log_error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
log_success() { ${QUIET:-false} || echo -e "${GREEN}$1${NC}"; }
log_warning() { ${QUIET:-false} || echo -e "${YELLOW}$1${NC}"; }
log_info() { ${QUIET:-false} || echo -e "${BLUE}$1${NC}"; }
log_verbose() { ${VERBOSE:-false} && echo -e "${CYAN}$1${NC}"; }
log_normal() { ${QUIET:-false} || echo "$1"; }

# -------------------------------------------
# Initialize project root
# -------------------------------------------
init_project_root() {
    PROJECT_ROOT="$(find_project_root)" || {
        print_error "Not a git repository. Please run from within a git project."
        exit 1
    }
}

# -------------------------------------------
# Load notes configuration from .notesrc
# -------------------------------------------
load_notes_config() {
    local config_file="$PROJECT_ROOT/notes/.notesrc"

    if [ -f "$config_file" ]; then
        # Parse JSON config (basic parsing without jq dependency)
        EXCLUSION_METHOD=$(grep -o '"exclusion_method"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | cut -d'"' -f4)
        WORKTREE_DIR=$(grep -o '"worktree"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | cut -d'"' -f4)
        WORKTREE_DIR="${WORKTREE_DIR#./}"  # Remove leading ./
        BRANCH_NAME=$(grep -o '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | cut -d'"' -f4)
        EXCLUDE_PATTERNS=$(grep -o '"exclude_patterns"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | cut -d'"' -f4)
    else
        # Default configuration
        EXCLUSION_METHOD="exclude"
        WORKTREE_DIR="notes"
        BRANCH_NAME="notes"
        EXCLUDE_PATTERNS=""
    fi

    NOTES_ROOT="$PROJECT_ROOT/$WORKTREE_DIR"

    # Set exclusion file based on method
    if [ "$EXCLUSION_METHOD" = "gitignore" ]; then
        EXCLUSION_FILE="$PROJECT_ROOT/.gitignore"
    else
        EXCLUSION_FILE="$PROJECT_ROOT/.git/info/exclude"
    fi
}

# -------------------------------------------
# Verify notes worktree exists
# -------------------------------------------
verify_notes_worktree() {
    if [ ! -d "$NOTES_ROOT/.git" ] && [ ! -f "$NOTES_ROOT/.git" ]; then
        print_error "Notes worktree not found at ./$WORKTREE_DIR"
        echo "Run: git worktree add ./$WORKTREE_DIR <branch-name>"
        exit 1
    fi
}

# Exclusion markers used in gitignore/exclude files
EXCLUDE_MARKER="# >>> sync-notes managed entries >>>"
EXCLUDE_END="# <<< sync-notes managed entries <<<"
