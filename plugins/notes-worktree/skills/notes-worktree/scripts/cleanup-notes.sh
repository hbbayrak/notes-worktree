#!/bin/bash
# Cleanup notes worktree issues
# - Remove dangling symlinks (targets deleted in notes)
# - Clean stale exclusion entries (paths no longer exist)
# - Standalone script for quick fixes without full sync

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
FIX_DANGLING=false
FIX_STALE=false
FIX_ALL=false
DRY_RUN=false
VERBOSE=false
QUIET=false

show_help() {
    echo "Usage: cleanup-notes.sh [OPTIONS]"
    echo ""
    echo "Clean up notes worktree issues."
    echo ""
    echo "Options:"
    echo "  --dangling    Remove broken symlinks (target missing)"
    echo "  --stale       Clean stale exclusion entries"
    echo "  --all         Fix everything (default if no options given)"
    echo "  --dry-run     Show what would be done without making changes"
    echo "  -v, --verbose Show detailed output"
    echo "  -q, --quiet   Show only errors and summary"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./cleanup-notes.sh              # Fix all issues"
    echo "  ./cleanup-notes.sh --dangling   # Only fix broken symlinks"
    echo "  ./cleanup-notes.sh --dry-run    # Preview what would be fixed"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dangling)
            FIX_DANGLING=true
            shift
            ;;
        --stale)
            FIX_STALE=true
            shift
            ;;
        --all)
            FIX_ALL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Default to --all if no specific option given
if ! $FIX_DANGLING && ! $FIX_STALE && ! $FIX_ALL; then
    FIX_ALL=true
fi

if $FIX_ALL; then
    FIX_DANGLING=true
    FIX_STALE=true
fi

# -------------------------------------------
# Resolve paths (symlink-safe using git)
# -------------------------------------------
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$PROJECT_ROOT" ]; then
    print_error "Not a git repository."
    exit 1
fi

# -------------------------------------------
# Load configuration
# -------------------------------------------
CONFIG_FILE="$PROJECT_ROOT/notes/.notesrc"
if [ -f "$CONFIG_FILE" ]; then
    EXCLUSION_METHOD=$(grep -o '"exclusion_method"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    WORKTREE_DIR=$(grep -o '"worktree"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    WORKTREE_DIR="${WORKTREE_DIR#./}"
else
    EXCLUSION_METHOD="exclude"
    WORKTREE_DIR="notes"
fi

NOTES_ROOT="$PROJECT_ROOT/$WORKTREE_DIR"

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
    exit 1
fi

# -------------------------------------------
# Header
# -------------------------------------------
if ! $QUIET; then
    echo ""
    echo "=========================================="
    if $DRY_RUN; then
        echo "  Notes Cleanup (DRY RUN)"
    else
        echo "  Notes Cleanup"
    fi
    echo "=========================================="
    echo ""
fi

# -------------------------------------------
# Fix dangling symlinks
# -------------------------------------------
DANGLING_COUNT=0
STALE_COUNT=0

if $FIX_DANGLING; then
    if ! $QUIET; then
        echo "Checking for dangling symlinks..."
    fi

    while IFS= read -r -d '' symlink; do
        target=$(readlink "$symlink")
        symlink_dir="$(dirname "$symlink")"
        full_target="$symlink_dir/$target"

        if [ ! -f "$full_target" ]; then
            rel_path="${symlink#$PROJECT_ROOT/}"
            ((DANGLING_COUNT++))

            if $DRY_RUN; then
                print_warning "[DRY-RUN] Would remove: $rel_path"
            else
                if $VERBOSE; then
                    print_warning "Removing: $rel_path -> $target (missing)"
                elif ! $QUIET; then
                    print_warning "Removing: $rel_path"
                fi
                rm -f "$symlink"
            fi
        fi
    done < <(find "$PROJECT_ROOT" \
        -name "*.md" \
        -type l \
        -not -path "$PROJECT_ROOT/$WORKTREE_DIR/*" \
        -not -path "$PROJECT_ROOT/.git/*" \
        -not -path "*/node_modules/*" \
        -print0 2>/dev/null)

    if ! $QUIET; then
        if [ $DANGLING_COUNT -eq 0 ]; then
            print_success "  No dangling symlinks found"
        else
            if $DRY_RUN; then
                print_info "  Would remove $DANGLING_COUNT dangling symlinks"
            else
                print_success "  Removed $DANGLING_COUNT dangling symlinks"
            fi
        fi
        echo ""
    fi
fi

# -------------------------------------------
# Fix stale exclusion entries
# -------------------------------------------
if $FIX_STALE; then
    if ! $QUIET; then
        echo "Checking for stale exclusion entries..."
    fi

    if [ -f "$EXCLUSION_FILE" ]; then
        # Collect stale entries
        declare -a STALE_ENTRIES=()
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
                # Skip comments, empty lines, and special entries
                if [[ "$line" =~ ^# ]] || [[ -z "$line" ]] || [[ "$line" == "/$WORKTREE_DIR/" ]] || [[ "$line" == "/scripts" ]]; then
                    continue
                fi
                # Skip pattern entries for gitignore method
                if [[ "$line" == "**/README.md" ]] || [[ "$line" == "CLAUDE.md" ]] || [[ "$line" == "!/README.md" ]]; then
                    continue
                fi

                check_path="$PROJECT_ROOT/$line"
                if [ ! -L "$check_path" ] && [ ! -f "$check_path" ]; then
                    STALE_ENTRIES+=("$line")
                    ((STALE_COUNT++))
                fi
            fi
        done < "$EXCLUSION_FILE"

        if [ ${#STALE_ENTRIES[@]} -gt 0 ]; then
            for entry in "${STALE_ENTRIES[@]}"; do
                if $DRY_RUN; then
                    print_warning "[DRY-RUN] Would remove entry: $entry"
                else
                    if $VERBOSE || ! $QUIET; then
                        print_warning "Removing entry: $entry"
                    fi
                fi
            done

            # Actually remove stale entries by rebuilding the managed section
            if ! $DRY_RUN; then
                # Extract content before and after managed section
                BEFORE_MARKER=$(sed -n "1,/$EXCLUDE_MARKER/p" "$EXCLUSION_FILE" | head -n -1)
                AFTER_MARKER=$(sed -n "/$EXCLUDE_END/,\$p" "$EXCLUSION_FILE" | tail -n +2)

                # Rebuild with valid entries only
                {
                    echo "$BEFORE_MARKER"
                    echo "$EXCLUDE_MARKER"

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
                            # Check if this line is stale
                            is_stale=false
                            for stale in "${STALE_ENTRIES[@]}"; do
                                if [[ "$line" == "$stale" ]]; then
                                    is_stale=true
                                    break
                                fi
                            done
                            if ! $is_stale; then
                                echo "$line"
                            fi
                        fi
                    done < "$EXCLUSION_FILE"

                    echo "$EXCLUDE_END"
                    echo "$AFTER_MARKER"
                } > "$EXCLUSION_FILE.tmp"

                mv "$EXCLUSION_FILE.tmp" "$EXCLUSION_FILE"
            fi
        fi

        if ! $QUIET; then
            if [ $STALE_COUNT -eq 0 ]; then
                print_success "  No stale exclusion entries found"
            else
                if $DRY_RUN; then
                    print_info "  Would remove $STALE_COUNT stale entries"
                else
                    print_success "  Removed $STALE_COUNT stale entries"
                fi
            fi
            echo ""
        fi
    else
        if ! $QUIET; then
            print_info "  No exclusion file found at $EXCLUSION_FILE"
            echo ""
        fi
    fi
fi

# -------------------------------------------
# Summary
# -------------------------------------------
TOTAL_ISSUES=$((DANGLING_COUNT + STALE_COUNT))

if $QUIET; then
    if $DRY_RUN; then
        echo "would_fix: $TOTAL_ISSUES"
    else
        echo "fixed: $TOTAL_ISSUES"
    fi
else
    echo "=========================================="
    if $DRY_RUN; then
        if [ $TOTAL_ISSUES -eq 0 ]; then
            print_success "No issues found"
        else
            print_warning "Would fix $TOTAL_ISSUES issues"
            echo ""
            echo "Run without --dry-run to apply changes"
        fi
    else
        if [ $TOTAL_ISSUES -eq 0 ]; then
            print_success "No issues found"
        else
            print_success "Fixed $TOTAL_ISSUES issues"
        fi
    fi
    echo "=========================================="
    echo ""
fi

exit 0
