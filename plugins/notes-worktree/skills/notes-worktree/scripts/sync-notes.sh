#!/bin/bash
# Sync documentation files between main project and notes worktree
# - Forward sync: Move .md files from main to notes, create symlinks
# - Reverse sync: Create symlinks for files in notes lacking them
# - Updates exclusion file based on .notesrc configuration
# - Supports dry-run, cleanup, verbose/quiet modes, and watch mode

set -euo pipefail

# Source common utilities
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
DRY_RUN=false
CLEANUP=false
VERBOSE=false
QUIET=false
WATCH=false
INTERACTIVE=true

show_help() {
    echo "Usage: sync-notes.sh [OPTIONS]"
    echo ""
    echo "Sync documentation files between main project and notes worktree."
    echo ""
    echo "Options:"
    echo "  --dry-run        Show what would happen without making changes"
    echo "  --cleanup        Remove dangling symlinks and stale exclusions"
    echo "  -v, --verbose    Show detailed output"
    echo "  -q, --quiet      Show only errors"
    echo "  --watch          Watch for file changes and auto-sync"
    echo "  --no-interactive Skip interactive conflict prompts"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./sync-notes.sh                    # Normal sync"
    echo "  ./sync-notes.sh --dry-run          # Preview changes"
    echo "  ./sync-notes.sh --cleanup          # Fix dangling symlinks"
    echo "  ./sync-notes.sh --watch            # Auto-sync on changes"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --cleanup)
            CLEANUP=true
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
        --watch)
            WATCH=true
            shift
            ;;
        --no-interactive)
            INTERACTIVE=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Verbose and quiet are mutually exclusive
if $VERBOSE && $QUIET; then
    log_error "--verbose and --quiet cannot be used together"
    exit 1
fi

# -------------------------------------------
# Resolve paths and load configuration
# -------------------------------------------
init_project_root
load_notes_config
verify_notes_worktree

# Keep notes/scripts pointed at the running plugin version (heals post-upgrade staleness)
if ! $DRY_RUN; then
    ensure_scripts_symlink
    if ${SCRIPTS_SYMLINK_REPAIRED:-false}; then
        log_normal "Refreshed notes/scripts symlink to the current plugin version"
    fi
fi

# -------------------------------------------
# Watch mode
# -------------------------------------------
if $WATCH; then
    log_info "Watching for changes... (Ctrl+C to stop)"
    log_info "Project: $PROJECT_ROOT"
    log_info "Notes: $NOTES_ROOT"
    echo ""

    # Check for fswatch (macOS) or inotifywait (Linux)
    if command -v fswatch &> /dev/null; then
        fswatch -o "$PROJECT_ROOT" --include '\.md$' --exclude "$NOTES_ROOT" | while read -r; do
            echo "[$(date '+%H:%M:%S')] Change detected, syncing..."
            "$0" --quiet --no-interactive
            echo "[$(date '+%H:%M:%S')] Sync complete"
        done
    elif command -v inotifywait &> /dev/null; then
        while true; do
            inotifywait -r -e modify,create,delete,move "$PROJECT_ROOT" --include '.*\.md$' --exclude "$NOTES_ROOT" 2>/dev/null
            echo "[$(date '+%H:%M:%S')] Change detected, syncing..."
            "$0" --quiet --no-interactive
            echo "[$(date '+%H:%M:%S')] Sync complete"
        done
    else
        log_error "Watch mode requires fswatch (macOS) or inotifywait (Linux)"
        echo ""
        echo "Install with:"
        echo "  macOS:  brew install fswatch"
        echo "  Ubuntu: sudo apt-get install inotify-tools"
        echo "  Fedora: sudo dnf install inotify-tools"
        exit 1
    fi
    exit 0
fi

# -------------------------------------------
# Dry-run wrapper
# -------------------------------------------
do_action() {
    local description="$1"
    shift
    if $DRY_RUN; then
        log_warning "[DRY-RUN] Would: $description"
        return 0
    else
        log_verbose "  $description"
        "$@"
    fi
}

# -------------------------------------------
# Portable mtime helper (epoch seconds)
# -------------------------------------------
get_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || date -r "$1" +%s 2>/dev/null || echo 0; }

# -------------------------------------------
# Interactive conflict resolution
# -------------------------------------------
resolve_conflict() {
    local src_file="$1"
    local dest_file="$2"
    local rel_path="$3"

    if ! $INTERACTIVE; then
        # Non-interactive: newer side wins (notes wins on tie), no .bak
        local src_mtime dest_mtime
        src_mtime=$(get_mtime "$src_file")
        dest_mtime=$(get_mtime "$dest_file")
        if [ "$src_mtime" -gt "$dest_mtime" ]; then
            log_warning "    Files differ! Main is newer; promoting main -> notes: $rel_path"
            do_action "copy main to notes" cp "$src_file" "$dest_file"
            do_action "remove main file" rm -f "$src_file"
        else
            log_warning "    Files differ! Notes is newer or equal; keeping notes: $rel_path"
            do_action "remove main file" rm -f "$src_file"
        fi
        return 0
    fi

    # Get file info
    local src_size=$(wc -c < "$src_file" | tr -d ' ')
    local dest_size=$(wc -c < "$dest_file" | tr -d ' ')
    local src_date=$(date -r "$src_file" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "$src_file" 2>/dev/null | cut -d' ' -f1-2)
    local dest_date=$(date -r "$dest_file" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "$dest_file" 2>/dev/null | cut -d' ' -f1-2)

    echo ""
    log_warning "Conflict: $rel_path"
    echo "  Main version:  $src_size bytes, modified $src_date"
    echo "  Notes version: $dest_size bytes, modified $dest_date"
    echo ""
    echo "  [d]iff  [m]ain (keep main)  [n]otes (keep notes)  [s]kip  [b]ackup both"
    echo ""

    while true; do
        read -p "  Choice: " choice
        case "$choice" in
            d|D)
                echo ""
                diff -u "$dest_file" "$src_file" || true
                echo ""
                ;;
            m|M)
                log_info "  Keeping main version"
                do_action "copy main to notes" cp "$src_file" "$dest_file"
                do_action "remove main file" rm -f "$src_file"
                return 0
                ;;
            n|N)
                log_info "  Keeping notes version"
                do_action "remove main file" rm -f "$src_file"
                return 0
                ;;
            s|S)
                log_info "  Skipping"
                return 1
                ;;
            b|B)
                log_info "  Backing up both versions"
                do_action "backup main" cp "$src_file" "$src_file.main.bak"
                do_action "backup notes" cp "$dest_file" "$dest_file.notes.bak"
                do_action "remove main file" rm -f "$src_file"
                return 0
                ;;
            *)
                echo "  Invalid choice. Use d/m/n/s/b"
                ;;
        esac
    done
}

# -------------------------------------------
# Cleanup functions
# -------------------------------------------
cleanup_dangling_symlinks() {
    local count=0
    log_normal ""
    log_normal "Checking for dangling symlinks..."

    while IFS= read -r -d '' symlink; do
        target=$(readlink "$symlink")
        symlink_dir="$(dirname "$symlink")"
        full_target="$symlink_dir/$target"

        if [ ! -f "$full_target" ]; then
            rel_path="${symlink#$PROJECT_ROOT/}"
            if $DRY_RUN; then
                log_warning "[DRY-RUN] Would remove dangling symlink: $rel_path"
            else
                log_warning "  Removing dangling symlink: $rel_path"
                rm -f "$symlink"
            fi
            ((count++)) || true
        fi
    done < <(find "$PROJECT_ROOT" \
        -name "*.md" \
        -type l \
        -not -path "$PROJECT_ROOT/$WORKTREE_DIR/*" \
        -not -path "$PROJECT_ROOT/.git/*" \
        -not -path "*/node_modules/*" \
        -print0 2>/dev/null)

    if [ $count -eq 0 ]; then
        log_success "  No dangling symlinks found"
    else
        log_success "  Cleaned up $count dangling symlinks"
    fi
}

cleanup_stale_exclusions() {
    if [ ! -f "$EXCLUSION_FILE" ]; then
        return
    fi

    log_normal ""
    log_normal "Checking for stale exclusion entries..."

    local stale_entries=()
    local in_managed_section=false

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
            if [[ "$line" == "*.md" ]] || [[ "$line" == "!/README.md" ]] || [[ "$line" == "!"* ]]; then
                continue
            fi

            check_path="$PROJECT_ROOT/$line"
            if [ ! -L "$check_path" ] && [ ! -f "$check_path" ]; then
                stale_entries+=("$line")
            fi
        fi
    done < "$EXCLUSION_FILE"

    if [ ${#stale_entries[@]} -eq 0 ]; then
        log_success "  No stale exclusion entries found"
        return
    fi

    for entry in "${stale_entries[@]}"; do
        if $DRY_RUN; then
            log_warning "[DRY-RUN] Would remove stale entry: $entry"
        else
            log_warning "  Removing stale entry: $entry"
        fi
    done

    # We'll rebuild exclusions in the update step, stale entries won't be included
    log_success "  Found ${#stale_entries[@]} stale entries (will be cleaned in exclusion update)"
}

# -------------------------------------------
# Main sync
# -------------------------------------------
if ! $QUIET; then
    echo ""
    echo "=========================================="
    if $DRY_RUN; then
        echo "  Notes Worktree Sync (DRY RUN)"
    else
        echo "  Notes Worktree Sync"
    fi
    echo "=========================================="
    log_info "Project root: $PROJECT_ROOT"
    log_info "Notes root: $NOTES_ROOT"
    log_info "Exclusion method: $EXCLUSION_METHOD"
    echo ""
fi

# Run cleanup if requested
if $CLEANUP; then
    cleanup_dangling_symlinks
    cleanup_stale_exclusions
fi

# Create temp file for tracking paths (unique to avoid races under --watch)
TEMP_PATHS="$(mktemp "${TMPDIR:-/tmp}/sync-notes-paths.XXXXXX")"
trap 'rm -f "$TEMP_PATHS"' EXIT
$DRY_RUN || rm -f "$TEMP_PATHS"

# -------------------------------------------
# Exclusion test (path-aware; see notes_path_excluded in _common.sh)
# -------------------------------------------
# Takes a path relative to the project/notes root (e.g. "docs/superpowers/x.md").
should_exclude_file() {
    notes_path_excluded "$1"
}

# -------------------------------------------
# Forward Sync: Main → Notes
# -------------------------------------------
log_normal "Forward sync: Moving .md files to notes..."
log_normal ""

FORWARD_COUNT=0

find "$PROJECT_ROOT" \
    -name "*.md" \
    -not -path "$PROJECT_ROOT/README.md" \
    -not -path "$PROJECT_ROOT/node_modules/*" \
    -not -path "$PROJECT_ROOT/.git/*" \
    -not -path "$PROJECT_ROOT/$WORKTREE_DIR/*" \
    -not -path "*/node_modules/*" \
    2>/dev/null | while read -r src_file; do

    # Calculate relative path from project root
    rel_path="${src_file#$PROJECT_ROOT/}"
    dest_file="$NOTES_ROOT/$rel_path"
    dest_dir="$(dirname "$dest_file")"

    # Skip if already a symlink
    if [ -L "$src_file" ]; then
        log_verbose "  SKIP (symlink): $rel_path"
        continue
    fi

    # Skip if file matches exclude patterns
    if should_exclude_file "$rel_path"; then
        log_verbose "  SKIP (excluded): $rel_path"
        continue
    fi

    # Track for exclusion (after filtering)
    if ! $DRY_RUN; then
        echo "$rel_path" >> "$TEMP_PATHS"
    fi

    log_normal "  Processing: $rel_path"
    ((FORWARD_COUNT++)) || true

    # Create destination directory
    do_action "create directory $dest_dir" mkdir -p "$dest_dir"

    # Move file to notes (if not already there)
    if [ -f "$src_file" ] && [ ! -f "$dest_file" ]; then
        do_action "move to notes" mv "$src_file" "$dest_file"
        log_normal "    Moved to notes"
    elif [ -f "$dest_file" ]; then
        # File exists in both places - check if different
        if ! cmp -s "$src_file" "$dest_file"; then
            if ! resolve_conflict "$src_file" "$dest_file" "$rel_path"; then
                continue  # User chose to skip
            fi
        else
            do_action "remove duplicate" rm -f "$src_file"
            log_normal "    Using existing notes version (identical)"
        fi
    fi

    # Create relative symlink
    if ! $DRY_RUN; then
        src_dir="$(dirname "$src_file")"
        rel_to_notes="$(python3 -c 'import os.path,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$dest_file" "$src_dir")"
        ln -sf "$rel_to_notes" "$src_file"
        log_normal "    Symlinked: $rel_to_notes"

        # Auto-add docs to .gitignore (only the root README is kept in main)
        if [ "$EXCLUSION_METHOD" = "gitignore" ]; then
            filename=$(basename "$rel_path")
            if [[ "$filename" != "README.md" ]]; then
                # Untrack if previously tracked
                git -C "$PROJECT_ROOT" rm --cached "$rel_path" 2>/dev/null || true
            fi
        fi
    else
        log_warning "[DRY-RUN] Would create symlink: $rel_path"
    fi
done || true  # tolerate non-zero find exit under pipefail

log_normal ""

# -------------------------------------------
# Reverse Sync: Notes → Main
# -------------------------------------------
log_normal "Reverse sync: Creating symlinks for notes files..."
log_normal ""

REVERSE_COUNT=0

find "$NOTES_ROOT" \
    -name "*.md" \
    -not -path "$NOTES_ROOT/.git/*" \
    -not -name "*.bak" \
    2>/dev/null | while read -r notes_file; do

    # Calculate relative path from notes root
    rel_path="${notes_file#$NOTES_ROOT/}"

    # Skip internal notes files
    if [[ "$rel_path" == ".notesrc" ]] || [[ "$rel_path" == ".gitignore" ]]; then
        continue
    fi

    # Always skip root README.md - the notes branch README is internal documentation
    # about the notes branch itself, not project documentation
    if [[ "$rel_path" == "README.md" ]]; then
        log_verbose "  SKIP (notes branch internal README): $rel_path"
        continue
    fi

    # Skip if file matches exclude patterns
    if should_exclude_file "$rel_path"; then
        log_verbose "  SKIP (excluded): $rel_path"
        continue
    fi

    # Target location in main project
    target_file="$PROJECT_ROOT/$rel_path"
    target_dir="$(dirname "$target_file")"

    # Track for exclusion (after filtering)
    if ! $DRY_RUN; then
        echo "$rel_path" >> "$TEMP_PATHS"
    fi

    # Skip if symlink already exists and is correct
    if [ -L "$target_file" ]; then
        # Verify symlink points to correct location
        current_target="$(readlink "$target_file")"
        expected_rel="$(python3 -c 'import os.path,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$notes_file" "$target_dir")"
        if [ "$current_target" = "$expected_rel" ]; then
            log_verbose "  OK: $rel_path"
            continue  # Symlink is correct, skip silently
        fi
        log_normal "  Fixing symlink: $rel_path"
        do_action "remove old symlink" rm "$target_file"
    elif [ -f "$target_file" ]; then
        # Regular file exists - should have been caught by forward sync
        log_verbose "  SKIP (regular file): $rel_path"
        continue
    else
        # Skip if parent directory doesn't exist (respect branch structure)
        if [ ! -d "$target_dir" ]; then
            log_verbose "  SKIP (directory doesn't exist): $rel_path"
            continue
        fi
        log_normal "  Creating symlink: $rel_path"
        ((REVERSE_COUNT++)) || true
    fi

    # Create relative symlink
    if ! $DRY_RUN; then
        rel_to_notes="$(python3 -c 'import os.path,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$notes_file" "$target_dir")"
        ln -sf "$rel_to_notes" "$target_file"
        log_normal "    -> $rel_to_notes"

        # Auto-add docs to .gitignore (only the root README is kept in main)
        if [ "$EXCLUSION_METHOD" = "gitignore" ]; then
            filename=$(basename "$rel_path")
            if [[ "$filename" != "README.md" ]]; then
                # Untrack if previously tracked
                git -C "$PROJECT_ROOT" rm --cached "$rel_path" 2>/dev/null || true
            fi
        fi
    else
        log_warning "[DRY-RUN] Would create symlink: $rel_path"
    fi
done || true  # tolerate non-zero find exit under pipefail

log_normal ""

# -------------------------------------------
# Update exclusion file
# -------------------------------------------
log_normal "Updating exclusions in $EXCLUSION_FILE..."

if $DRY_RUN; then
    log_warning "[DRY-RUN] Would update exclusion file"
else
    # Create exclusion file if it doesn't exist
    touch "$EXCLUSION_FILE"

    # Remove old managed entries (literal-line match, immune to regex metachars)
    if grep -qF "$EXCLUDE_MARKER" "$EXCLUSION_FILE" 2>/dev/null; then
        awk -v start="$EXCLUDE_MARKER" -v end="$EXCLUDE_END" '
            $0 == start { skip=1 }
            skip { if ($0 == end) skip=0; next }
            { print }
        ' "$EXCLUSION_FILE" > "$EXCLUSION_FILE.tmp" && mv "$EXCLUSION_FILE.tmp" "$EXCLUSION_FILE"
    fi

    # Strip trailing blank lines before appending managed section (idempotent)
    awk 'NF{p=NR} {a[NR]=$0} END{for(i=1;i<=p;i++) print a[i]}' "$EXCLUSION_FILE" > "$EXCLUSION_FILE.tmp" 2>/dev/null && mv "$EXCLUSION_FILE.tmp" "$EXCLUSION_FILE" || true

    # Add new managed entries
    {
        echo "$EXCLUDE_MARKER"
        echo "# Notes worktree (tracked in notes branch)"
        echo "/$WORKTREE_DIR/"
        echo ""
        echo "# Documentation symlinks (all markdown files)"

        if [ "$EXCLUSION_METHOD" = "gitignore" ]; then
            # For .gitignore, ignore all markdown
            echo "*.md"
            echo ""
            echo "# Exceptions: keep these in main branch"
            echo "!/README.md"

            # Add exclusion patterns as exceptions (kept in main branch).
            # Directory subtrees are normalized to "!dir/**" so nested markdown
            # is re-included under the blanket "*.md" ignore.
            if [ -n "$EXCLUDE_PATTERNS" ]; then
                IFS=',' read -ra PATTERNS <<< "$EXCLUDE_PATTERNS"
                for pattern in "${PATTERNS[@]}"; do
                    to_gitignore_negation "$pattern"
                done
            fi
        else
            # For .git/info/exclude, list specific files
            if [ -f "$TEMP_PATHS" ]; then
                sort -u "$TEMP_PATHS"
            fi
        fi

        echo "$EXCLUDE_END"
    } >> "$EXCLUSION_FILE"

    rm -f "$TEMP_PATHS"
fi

# -------------------------------------------
# Update notes .gitignore
# -------------------------------------------
NOTES_GITIGNORE="$NOTES_ROOT/.gitignore"
log_normal "Updating notes/.gitignore..."

if $DRY_RUN; then
    log_warning "[DRY-RUN] Would update notes/.gitignore"
else
    # Generate expected content
    EXPECTED_CONTENT="# Scripts symlink (points to plugin)
/scripts

# Negate exclusions so files are tracked in notes branch
!*.md"

    # Add exclusion patterns (files to keep in main, not tracked in notes)
    if [ -n "$EXCLUDE_PATTERNS" ]; then
        EXPECTED_CONTENT="$EXPECTED_CONTENT

# Files excluded from notes (kept in main branch)"
        IFS=',' read -ra PATTERNS <<< "$EXCLUDE_PATTERNS"
        for pattern in "${PATTERNS[@]}"; do
            pattern=$(echo "$pattern" | xargs)  # trim whitespace
            EXPECTED_CONTENT="$EXPECTED_CONTENT
$pattern"
        done
    fi

    EXPECTED_CONTENT="$EXPECTED_CONTENT

# Ignore system files
.DS_Store
*.bak
*.main.bak
*.notes.bak
.sync-notes-paths.tmp"

    # Only update if content differs (avoid unnecessary changes)
    if [ ! -f "$NOTES_GITIGNORE" ] || [ "$(cat "$NOTES_GITIGNORE")" != "$EXPECTED_CONTENT" ]; then
        echo "$EXPECTED_CONTENT" > "$NOTES_GITIGNORE"
    fi
fi

# -------------------------------------------
# Summary
# -------------------------------------------
log_normal ""
if $DRY_RUN; then
    log_warning "DRY RUN COMPLETE - No changes were made"
else
    log_success "Sync complete!"
fi
log_normal ""
log_normal "Summary:"
log_normal "  Notes location: $NOTES_ROOT"
log_normal "  Exclusions: $EXCLUSION_FILE"
log_normal ""
log_normal "Next steps:"
log_normal "  cd $WORKTREE_DIR && git add -A && git commit -m 'Update docs'"
log_normal ""
