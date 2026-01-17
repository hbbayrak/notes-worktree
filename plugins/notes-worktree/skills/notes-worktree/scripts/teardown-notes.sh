#!/bin/bash
# Teardown notes worktree setup
# - Remove all documentation symlinks
# - Optionally convert symlinks back to real files
# - Remove scripts symlink
# - Clean exclusion file entries
# - Remove git worktree
# - Optionally delete the notes branch

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
KEEP_BRANCH=false
KEEP_FILES=false
FORCE=false
DRY_RUN=false

show_help() {
    echo "Usage: teardown-notes.sh [OPTIONS]"
    echo ""
    echo "Remove notes worktree setup and clean up all artifacts."
    echo ""
    echo "Options:"
    echo "  --keep-branch    Don't delete the notes branch"
    echo "  --keep-files     Convert symlinks back to real files before removal"
    echo "  --force          Skip confirmation prompts"
    echo "  --dry-run        Show what would be done without making changes"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./teardown-notes.sh                  # Full teardown with prompts"
    echo "  ./teardown-notes.sh --keep-files     # Keep docs as real files"
    echo "  ./teardown-notes.sh --force          # No confirmation prompts"
    echo ""
    echo "WARNING: This will remove the notes worktree and optionally the branch."
    echo "         Make sure to push any uncommitted changes first!"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-branch)
            KEEP_BRANCH=true
            shift
            ;;
        --keep-files)
            KEEP_FILES=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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

# -------------------------------------------
# Resolve paths and load configuration
# -------------------------------------------
init_project_root
load_notes_config

# Verify notes worktree exists (different check - just directory, not git)
if [ ! -d "$NOTES_ROOT" ]; then
    print_error "Notes worktree not found at ./$WORKTREE_DIR"
    exit 1
fi

# -------------------------------------------
# Pre-flight checks
# -------------------------------------------
echo ""
echo "=========================================="
if $DRY_RUN; then
    echo "  Notes Worktree Teardown (DRY RUN)"
else
    echo "  Notes Worktree Teardown"
fi
echo "=========================================="
echo ""
print_info "Project: $PROJECT_ROOT"
print_info "Notes: $NOTES_ROOT"
print_info "Branch: $BRANCH_NAME"
echo ""

# Check for uncommitted changes in notes
cd "$NOTES_ROOT"
UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
cd "$PROJECT_ROOT"

if [ "$UNCOMMITTED" -gt 0 ]; then
    print_warning "WARNING: $UNCOMMITTED uncommitted changes in notes branch!"
    echo ""
    if ! $FORCE; then
        read -p "Continue anyway? Changes will be lost! [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi
fi

# Check for unpushed commits
cd "$NOTES_ROOT"
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
UPSTREAM=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")
if [ -n "$UPSTREAM" ]; then
    UNPUSHED=$(git rev-list "$UPSTREAM..HEAD" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$UNPUSHED" -gt 0 ]; then
        print_warning "WARNING: $UNPUSHED unpushed commits in notes branch!"
        echo ""
        if ! $FORCE; then
            read -p "Continue anyway? Unpushed commits will be lost if branch is deleted! [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Aborted."
                exit 0
            fi
        fi
    fi
fi
cd "$PROJECT_ROOT"

# Confirmation
if ! $FORCE && ! $DRY_RUN; then
    echo "This will:"
    if $KEEP_FILES; then
        echo "  - Convert symlinks to real files (copy from notes)"
    else
        echo "  - Remove all documentation symlinks"
    fi
    echo "  - Remove scripts symlink"
    echo "  - Clean exclusion file entries"
    echo "  - Remove worktree at ./$WORKTREE_DIR"
    if ! $KEEP_BRANCH; then
        echo "  - Delete branch '$BRANCH_NAME'"
    fi
    echo ""
    read -p "Proceed with teardown? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""

# -------------------------------------------
# Step 1: Handle symlinks
# -------------------------------------------
echo "Step 1: Processing documentation symlinks..."

SYMLINK_COUNT=0
while IFS= read -r -d '' symlink; do
    rel_path="${symlink#$PROJECT_ROOT/}"
    ((SYMLINK_COUNT++))

    if $KEEP_FILES; then
        # Get the target file
        target=$(readlink "$symlink")
        symlink_dir="$(dirname "$symlink")"
        full_target="$symlink_dir/$target"

        if [ -f "$full_target" ]; then
            if $DRY_RUN; then
                print_info "[DRY-RUN] Would convert: $rel_path"
            else
                # Remove symlink and copy the actual file
                rm -f "$symlink"
                cp "$full_target" "$symlink"
                echo "  Converted: $rel_path"
            fi
        else
            if $DRY_RUN; then
                print_warning "[DRY-RUN] Would remove (target missing): $rel_path"
            else
                rm -f "$symlink"
                print_warning "  Removed (target missing): $rel_path"
            fi
        fi
    else
        if $DRY_RUN; then
            print_info "[DRY-RUN] Would remove: $rel_path"
        else
            rm -f "$symlink"
            echo "  Removed: $rel_path"
        fi
    fi
done < <(find "$PROJECT_ROOT" \
    -name "*.md" \
    -type l \
    -not -path "$PROJECT_ROOT/$WORKTREE_DIR/*" \
    -not -path "$PROJECT_ROOT/.git/*" \
    -not -path "*/node_modules/*" \
    -print0 2>/dev/null)

if [ $SYMLINK_COUNT -eq 0 ]; then
    echo "  No symlinks found"
fi
echo ""

# -------------------------------------------
# Step 2: Remove scripts symlink
# -------------------------------------------
echo "Step 2: Removing scripts symlink..."

SCRIPTS_LINK="$PROJECT_ROOT/scripts"
if [ -L "$SCRIPTS_LINK" ]; then
    if $DRY_RUN; then
        print_info "[DRY-RUN] Would remove: scripts"
    else
        rm -f "$SCRIPTS_LINK"
        echo "  Removed: scripts"
    fi
else
    echo "  No scripts symlink found"
fi
echo ""

# -------------------------------------------
# Step 3: Clean exclusion file
# -------------------------------------------
echo "Step 3: Cleaning exclusion entries..."

if [ -f "$EXCLUSION_FILE" ]; then
    if grep -q "$EXCLUDE_MARKER" "$EXCLUSION_FILE" 2>/dev/null; then
        if $DRY_RUN; then
            print_info "[DRY-RUN] Would remove managed entries from $EXCLUSION_FILE"
        else
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "/$EXCLUDE_MARKER/,/$EXCLUDE_END/d" "$EXCLUSION_FILE"
            else
                sed -i "/$EXCLUDE_MARKER/,/$EXCLUDE_END/d" "$EXCLUSION_FILE"
            fi
            echo "  Removed managed entries from $EXCLUSION_FILE"
        fi
    else
        echo "  No managed entries found in $EXCLUSION_FILE"
    fi
else
    echo "  No exclusion file at $EXCLUSION_FILE"
fi
echo ""

# -------------------------------------------
# Step 4: Remove worktree
# -------------------------------------------
echo "Step 4: Removing worktree..."

if [ -d "$NOTES_ROOT" ]; then
    if $DRY_RUN; then
        print_info "[DRY-RUN] Would remove worktree at ./$WORKTREE_DIR"
    else
        git worktree remove "./$WORKTREE_DIR" --force
        echo "  Removed worktree at ./$WORKTREE_DIR"
    fi
else
    echo "  Worktree already removed"
fi
echo ""

# -------------------------------------------
# Step 5: Optionally delete branch
# -------------------------------------------
if ! $KEEP_BRANCH; then
    echo "Step 5: Deleting branch..."

    if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
        if $DRY_RUN; then
            print_info "[DRY-RUN] Would delete branch '$BRANCH_NAME'"
        else
            git branch -D "$BRANCH_NAME"
            echo "  Deleted local branch '$BRANCH_NAME'"
        fi
    else
        echo "  Local branch '$BRANCH_NAME' not found"
    fi

    # Note about remote branch
    if git ls-remote --heads origin "$BRANCH_NAME" 2>/dev/null | grep -q "$BRANCH_NAME"; then
        print_warning "  Note: Remote branch 'origin/$BRANCH_NAME' still exists"
        echo "  To delete: git push origin --delete $BRANCH_NAME"
    fi
else
    echo "Step 5: Keeping branch '$BRANCH_NAME' (--keep-branch)"
fi
echo ""

# -------------------------------------------
# Summary
# -------------------------------------------
echo "=========================================="
if $DRY_RUN; then
    print_warning "DRY RUN COMPLETE - No changes were made"
else
    print_success "Teardown complete!"
fi
echo "=========================================="
echo ""

if ! $DRY_RUN; then
    if $KEEP_FILES; then
        echo "Documentation files have been converted to regular files."
    else
        echo "All documentation symlinks have been removed."
    fi

    if $KEEP_BRANCH; then
        echo ""
        echo "To restore later:"
        echo "  git worktree add ./$WORKTREE_DIR $BRANCH_NAME"
        echo "  ./scripts/sync-notes.sh"
    fi
fi
echo ""
