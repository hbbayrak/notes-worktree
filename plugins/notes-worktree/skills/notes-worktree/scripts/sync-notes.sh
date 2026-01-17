#!/bin/bash
# Sync documentation files between main project and notes worktree
# - Forward sync: Move .md files from main to notes, create symlinks
# - Reverse sync: Create symlinks for files in notes lacking them
# - Updates exclusion file based on .notesrc configuration

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
# Resolve paths
# -------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Handle case where script is in notes/scripts/ (accessed via symlink)
if [[ "$SCRIPT_DIR" == */notes/scripts ]] || [[ "$SCRIPT_DIR" == */*/scripts ]]; then
    # Script is inside the worktree
    NOTES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    PROJECT_ROOT="$(cd "$NOTES_ROOT/.." && pwd)"
else
    # Script accessed from project root /scripts symlink
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
    # Parse JSON config (basic parsing without jq dependency)
    EXCLUSION_METHOD=$(grep -o '"exclusion_method"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    WORKTREE_DIR=$(grep -o '"worktree"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    WORKTREE_DIR="${WORKTREE_DIR#./}"  # Remove leading ./
else
    # Default configuration
    EXCLUSION_METHOD="exclude"
    WORKTREE_DIR="notes"
fi

# Set exclusion file based on method
if [ "$EXCLUSION_METHOD" = "gitignore" ]; then
    EXCLUSION_FILE="$PROJECT_ROOT/.gitignore"
else
    EXCLUSION_FILE="$PROJECT_ROOT/.git/info/exclude"
fi

# Verify notes worktree exists
if [ ! -d "$NOTES_ROOT/.git" ] && [ ! -f "$NOTES_ROOT/.git" ]; then
    print_error "Notes worktree not found at ./$WORKTREE_DIR"
    echo "Run: git worktree add ./$WORKTREE_DIR <branch-name>"
    exit 1
fi

EXCLUDE_MARKER="# >>> sync-notes managed entries >>>"
EXCLUDE_END="# <<< sync-notes managed entries <<<"

echo ""
echo "=========================================="
echo "  Notes Worktree Sync"
echo "=========================================="
print_info "Project root: $PROJECT_ROOT"
print_info "Notes root: $NOTES_ROOT"
print_info "Exclusion method: $EXCLUSION_METHOD"
echo ""

# Create temp file for tracking paths
TEMP_PATHS="$PROJECT_ROOT/.sync-notes-paths.tmp"
rm -f "$TEMP_PATHS"

# -------------------------------------------
# Forward Sync: Main → Notes
# -------------------------------------------
echo "Forward sync: Moving .md files to notes..."
echo ""

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

    # Track for exclusion
    echo "$rel_path" >> "$TEMP_PATHS"

    # Skip if already a symlink
    if [ -L "$src_file" ]; then
        echo "  SKIP (symlink): $rel_path"
        continue
    fi

    echo "  Processing: $rel_path"

    # Create destination directory
    mkdir -p "$dest_dir"

    # Move file to notes (if not already there)
    if [ -f "$src_file" ] && [ ! -f "$dest_file" ]; then
        mv "$src_file" "$dest_file"
        echo "    Moved to notes"
    elif [ -f "$dest_file" ]; then
        # File exists in both places - check if different
        if ! cmp -s "$src_file" "$dest_file"; then
            print_warning "    Files differ! Backing up source to $rel_path.bak"
            mv "$src_file" "$src_file.bak"
        else
            rm -f "$src_file"
            echo "    Using existing notes version (identical)"
        fi
    fi

    # Create relative symlink
    src_dir="$(dirname "$src_file")"
    rel_to_notes="$(python3 -c "import os.path; print(os.path.relpath('$dest_file', '$src_dir'))")"
    ln -sf "$rel_to_notes" "$src_file"
    echo "    Symlinked: $rel_to_notes"
done

echo ""

# -------------------------------------------
# Reverse Sync: Notes → Main
# -------------------------------------------
echo "Reverse sync: Creating symlinks for notes files..."
echo ""

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

    # Target location in main project
    target_file="$PROJECT_ROOT/$rel_path"
    target_dir="$(dirname "$target_file")"

    # Track for exclusion
    echo "$rel_path" >> "$TEMP_PATHS"

    # Skip if symlink already exists and is correct
    if [ -L "$target_file" ]; then
        # Verify symlink points to correct location
        current_target="$(readlink "$target_file")"
        expected_rel="$(python3 -c "import os.path; print(os.path.relpath('$notes_file', '$target_dir'))")"
        if [ "$current_target" = "$expected_rel" ]; then
            continue  # Symlink is correct, skip silently
        fi
        echo "  Fixing symlink: $rel_path"
        rm "$target_file"
    elif [ -f "$target_file" ]; then
        # Regular file exists - should have been caught by forward sync
        continue
    else
        echo "  Creating symlink: $rel_path"
    fi

    # Create parent directory if needed
    mkdir -p "$target_dir"

    # Create relative symlink
    rel_to_notes="$(python3 -c "import os.path; print(os.path.relpath('$notes_file', '$target_dir'))")"
    ln -sf "$rel_to_notes" "$target_file"
    echo "    -> $rel_to_notes"
done

echo ""

# -------------------------------------------
# Update exclusion file
# -------------------------------------------
echo "Updating exclusions in $EXCLUSION_FILE..."

# Create exclusion file if it doesn't exist
touch "$EXCLUSION_FILE"

# Remove old managed entries
if grep -q "$EXCLUDE_MARKER" "$EXCLUSION_FILE" 2>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "/$EXCLUDE_MARKER/,/$EXCLUDE_END/d" "$EXCLUSION_FILE"
    else
        sed -i "/$EXCLUDE_MARKER/,/$EXCLUDE_END/d" "$EXCLUSION_FILE"
    fi
fi

# Add new managed entries
{
    echo ""
    echo "$EXCLUDE_MARKER"
    echo "# Notes worktree (tracked in notes branch)"
    echo "/$WORKTREE_DIR/"
    echo "/scripts"
    echo ""
    echo "# Documentation symlinks"

    if [ "$EXCLUSION_METHOD" = "gitignore" ]; then
        # For .gitignore, use patterns
        echo "**/README.md"
        echo "CLAUDE.md"
        echo ""
        echo "# Exception: keep root README in main branch"
        echo "!/README.md"
    else
        # For .git/info/exclude, list specific files
        if [ -f "$TEMP_PATHS" ]; then
            sort -u "$TEMP_PATHS"
        fi
    fi

    echo "$EXCLUDE_END"
} >> "$EXCLUSION_FILE"

rm -f "$TEMP_PATHS"

# -------------------------------------------
# Update notes .gitignore
# -------------------------------------------
NOTES_GITIGNORE="$NOTES_ROOT/.gitignore"
echo "Updating notes/.gitignore..."

cat > "$NOTES_GITIGNORE" << 'IGNOREEOF'
# Negate exclusions so files are tracked in notes branch
!**/README.md
!CLAUDE.md
!scripts/

# Ignore system files
.DS_Store
*.bak
.sync-notes-paths.tmp
IGNOREEOF

# -------------------------------------------
# Summary
# -------------------------------------------
echo ""
print_success "Sync complete!"
echo ""
echo "Summary:"
echo "  Notes location: $NOTES_ROOT"
echo "  Exclusions: $EXCLUSION_FILE"
echo ""
echo "Next steps:"
echo "  cd $WORKTREE_DIR && git add -A && git commit -m 'Update docs'"
echo ""
