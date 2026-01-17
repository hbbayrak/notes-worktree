#!/bin/bash
# Show status of notes worktree setup
# - Check synced files (symlinks pointing to notes)
# - Detect dangling symlinks (target missing)
# - Find notes files without symlinks
# - Check for stale exclusion entries
# - Show notes branch git status

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_info() { echo -e "${BLUE}$1${NC}"; }

# -------------------------------------------
# Parse arguments
# -------------------------------------------
VERBOSE=false
QUIET=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            echo "Usage: status-notes.sh [OPTIONS]"
            echo ""
            echo "Show status of notes worktree setup."
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show detailed file listings"
            echo "  -q, --quiet      Show only errors and summary counts"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

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

# Verify we're in a git repo
if ! git -C "$PROJECT_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not a git repository."
    exit 1
fi

# -------------------------------------------
# Load configuration
# -------------------------------------------
CONFIG_FILE="$NOTES_ROOT/.notesrc"
if [ -f "$CONFIG_FILE" ]; then
    EXCLUSION_METHOD=$(grep -o '"exclusion_method"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    WORKTREE_DIR=$(grep -o '"worktree"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    WORKTREE_DIR="${WORKTREE_DIR#./}"
    BRANCH_NAME=$(grep -o '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
else
    EXCLUSION_METHOD="exclude"
    WORKTREE_DIR="notes"
    BRANCH_NAME="notes"
fi

if [ "$EXCLUSION_METHOD" = "gitignore" ]; then
    EXCLUSION_FILE="$PROJECT_ROOT/.gitignore"
else
    EXCLUSION_FILE="$PROJECT_ROOT/.git/info/exclude"
fi

EXCLUDE_MARKER="# >>> sync-notes managed entries >>>"
EXCLUDE_END="# <<< sync-notes managed entries <<<"

# Verify notes worktree exists
if [ ! -d "$NOTES_ROOT/.git" ] && [ ! -f "$NOTES_ROOT/.git" ]; then
    print_error "Notes worktree not found at ./$WORKTREE_DIR"
    echo "Run: git worktree add ./$WORKTREE_DIR <branch-name>"
    exit 1
fi

# -------------------------------------------
# Collect status information
# -------------------------------------------

# Arrays to hold results
declare -a SYNCED_FILES=()
declare -a DANGLING_SYMLINKS=()
declare -a NOTES_WITHOUT_SYMLINKS=()
declare -a STALE_EXCLUSIONS=()

# Find all .md symlinks in project (excluding notes dir)
while IFS= read -r -d '' symlink; do
    target=$(readlink "$symlink")
    rel_path="${symlink#$PROJECT_ROOT/}"

    # Resolve target path
    symlink_dir="$(dirname "$symlink")"
    full_target="$symlink_dir/$target"

    if [ -f "$full_target" ]; then
        SYNCED_FILES+=("$rel_path")
    else
        DANGLING_SYMLINKS+=("$rel_path")
    fi
done < <(find "$PROJECT_ROOT" \
    -name "*.md" \
    -type l \
    -not -path "$PROJECT_ROOT/$WORKTREE_DIR/*" \
    -not -path "$PROJECT_ROOT/.git/*" \
    -not -path "*/node_modules/*" \
    -print0 2>/dev/null)

# Find all .md files in notes that don't have symlinks in project
while IFS= read -r -d '' notes_file; do
    rel_path="${notes_file#$NOTES_ROOT/}"

    # Skip internal files
    if [[ "$rel_path" == ".gitignore" ]] || [[ "$rel_path" == ".notesrc" ]] || [[ "$rel_path" =~ \.bak$ ]]; then
        continue
    fi

    target_symlink="$PROJECT_ROOT/$rel_path"

    if [ ! -L "$target_symlink" ]; then
        NOTES_WITHOUT_SYMLINKS+=("$rel_path")
    fi
done < <(find "$NOTES_ROOT" \
    -name "*.md" \
    -type f \
    -not -path "$NOTES_ROOT/.git/*" \
    -print0 2>/dev/null)

# Check for stale exclusion entries
if [ -f "$EXCLUSION_FILE" ]; then
    in_managed_section=false
    while IFS= read -r line; do
        if [[ "$line" == "$EXCLUDE_MARKER" ]]; then
            in_managed_section=true
            continue
        fi
        if [[ "$line" == "$EXCLUDE_END" ]]; then
            in_managed_section=false
            continue
        fi

        if $in_managed_section; then
            # Skip comments and special entries
            if [[ "$line" =~ ^# ]] || [[ -z "$line" ]] || [[ "$line" == "/$WORKTREE_DIR/" ]] || [[ "$line" == "/scripts" ]]; then
                continue
            fi

            # Skip pattern entries for gitignore method
            if [[ "$line" == "**/README.md" ]] || [[ "$line" == "CLAUDE.md" ]] || [[ "$line" == "!/README.md" ]]; then
                continue
            fi

            # Check if the path exists (as a symlink)
            check_path="$PROJECT_ROOT/$line"
            if [ ! -L "$check_path" ] && [ ! -f "$check_path" ]; then
                STALE_EXCLUSIONS+=("$line")
            fi
        fi
    done < "$EXCLUSION_FILE"
fi

# Get notes branch git status
NOTES_UNCOMMITTED=0
NOTES_UNPUSHED=0
if [ -d "$NOTES_ROOT" ]; then
    cd "$NOTES_ROOT"
    NOTES_UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

    # Check for unpushed commits
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
    if [ -n "$CURRENT_BRANCH" ]; then
        UPSTREAM=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")
        if [ -n "$UPSTREAM" ]; then
            NOTES_UNPUSHED=$(git rev-list "$UPSTREAM..HEAD" 2>/dev/null | wc -l | tr -d ' ')
        else
            # No upstream, count all commits as "unpushed"
            NOTES_UNPUSHED=$(git rev-list HEAD 2>/dev/null | wc -l | tr -d ' ')
        fi
    fi
    cd "$PROJECT_ROOT"
fi

# -------------------------------------------
# Display status
# -------------------------------------------

if ! $QUIET; then
    echo ""
    echo "=========================================="
    echo "  Notes Worktree Status"
    echo "=========================================="
    print_info "Branch: $BRANCH_NAME"
    print_info "Worktree: ./$WORKTREE_DIR"
    echo ""
fi

# Files summary
SYNCED_COUNT=${#SYNCED_FILES[@]}
DANGLING_COUNT=${#DANGLING_SYMLINKS[@]}
MISSING_COUNT=${#NOTES_WITHOUT_SYMLINKS[@]}
STALE_COUNT=${#STALE_EXCLUSIONS[@]}

if ! $QUIET; then
    echo "Files:"
fi

if [ $SYNCED_COUNT -gt 0 ]; then
    if $QUIET; then
        echo "synced: $SYNCED_COUNT"
    else
        echo -e "  ${GREEN}✓${NC} $SYNCED_COUNT synced (symlink → notes file)"
    fi
    if $VERBOSE; then
        for f in "${SYNCED_FILES[@]}"; do
            echo "      $f"
        done
    fi
fi

if [ $DANGLING_COUNT -gt 0 ]; then
    if $QUIET; then
        echo "dangling: $DANGLING_COUNT"
    else
        echo -e "  ${YELLOW}⚠${NC} $DANGLING_COUNT dangling symlinks (target missing)"
    fi
    if $VERBOSE || ! $QUIET; then
        for f in "${DANGLING_SYMLINKS[@]}"; do
            echo -e "      ${YELLOW}$f${NC}"
        done
    fi
fi

if [ $MISSING_COUNT -gt 0 ]; then
    if $QUIET; then
        echo "unlinked: $MISSING_COUNT"
    else
        echo -e "  ${CYAN}○${NC} $MISSING_COUNT in notes without symlink"
    fi
    if $VERBOSE; then
        for f in "${NOTES_WITHOUT_SYMLINKS[@]}"; do
            echo "      $f"
        done
    fi
fi

if [ $SYNCED_COUNT -eq 0 ] && [ $DANGLING_COUNT -eq 0 ] && [ $MISSING_COUNT -eq 0 ]; then
    if ! $QUIET; then
        echo "  (no documentation files found)"
    fi
fi

if ! $QUIET; then
    echo ""
    echo "Exclusions ($EXCLUSION_METHOD):"
fi

# Count total managed exclusion entries
TOTAL_EXCLUSIONS=0
if [ -f "$EXCLUSION_FILE" ]; then
    in_managed_section=false
    while IFS= read -r line; do
        if [[ "$line" == "$EXCLUDE_MARKER" ]]; then
            in_managed_section=true
            continue
        fi
        if [[ "$line" == "$EXCLUDE_END" ]]; then
            in_managed_section=false
            continue
        fi
        if $in_managed_section && [[ ! "$line" =~ ^# ]] && [[ -n "$line" ]]; then
            ((TOTAL_EXCLUSIONS++))
        fi
    done < "$EXCLUSION_FILE"
fi

if [ $TOTAL_EXCLUSIONS -gt 0 ]; then
    if [ $STALE_COUNT -gt 0 ]; then
        if $QUIET; then
            echo "exclusions: $TOTAL_EXCLUSIONS ($STALE_COUNT stale)"
        else
            echo -e "  ${YELLOW}⚠${NC} $TOTAL_EXCLUSIONS entries ($STALE_COUNT stale)"
        fi
        if $VERBOSE || ! $QUIET; then
            for f in "${STALE_EXCLUSIONS[@]}"; do
                echo -e "      ${YELLOW}$f${NC} (stale)"
            done
        fi
    else
        if $QUIET; then
            echo "exclusions: $TOTAL_EXCLUSIONS"
        else
            echo -e "  ${GREEN}✓${NC} $TOTAL_EXCLUSIONS entries (all valid)"
        fi
    fi
else
    if ! $QUIET; then
        echo "  (no managed entries)"
    fi
fi

if ! $QUIET; then
    echo ""
    echo "Notes branch:"
fi

if [ $NOTES_UNCOMMITTED -gt 0 ]; then
    if $QUIET; then
        echo "uncommitted: $NOTES_UNCOMMITTED"
    else
        echo -e "  ${YELLOW}⚠${NC} $NOTES_UNCOMMITTED uncommitted changes"
    fi
else
    if ! $QUIET; then
        echo -e "  ${GREEN}✓${NC} Working tree clean"
    fi
fi

if [ $NOTES_UNPUSHED -gt 0 ]; then
    if $QUIET; then
        echo "unpushed: $NOTES_UNPUSHED"
    else
        echo -e "  ${CYAN}○${NC} $NOTES_UNPUSHED unpushed commits"
    fi
fi

# -------------------------------------------
# Recommendations
# -------------------------------------------
HAS_ISSUES=false

if [ $DANGLING_COUNT -gt 0 ] || [ $STALE_COUNT -gt 0 ]; then
    HAS_ISSUES=true
fi

if $HAS_ISSUES && ! $QUIET; then
    echo ""
    echo "Recommendations:"
    if [ $DANGLING_COUNT -gt 0 ] || [ $STALE_COUNT -gt 0 ]; then
        echo "  Run: ./scripts/sync-notes.sh --cleanup to fix issues"
    fi
fi

if [ $MISSING_COUNT -gt 0 ] && ! $QUIET; then
    echo ""
    echo "Note: Files in notes without symlinks may be intentional."
    echo "  Run: ./scripts/sync-notes.sh to create missing symlinks"
fi

if ! $QUIET; then
    echo ""
fi

# Exit with status code based on issues found
if [ $DANGLING_COUNT -gt 0 ]; then
    exit 1
fi
exit 0
