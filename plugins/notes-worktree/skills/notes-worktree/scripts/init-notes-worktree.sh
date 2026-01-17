#!/bin/bash
# Initialize a notes worktree for documentation management
# - Creates a new orphan branch for documentation
# - Sets up git worktree
# - Configures exclusions (local or shared)
# - Optionally syncs existing .md files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_info() { echo -e "${BLUE}$1${NC}"; }

# Resolve project root
if git rev-parse --git-dir > /dev/null 2>&1; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
else
    print_error "Not a git repository. Please run from within a git project."
    exit 1
fi

cd "$PROJECT_ROOT"

echo ""
echo "=========================================="
echo "  Notes Worktree Setup"
echo "=========================================="
echo ""
print_info "Project: $PROJECT_ROOT"
echo ""

# -------------------------------------------
# Prompt for branch name
# -------------------------------------------
read -p "Branch name for documentation [notes]: " BRANCH_NAME
BRANCH_NAME="${BRANCH_NAME:-notes}"

# Validate branch name
if [[ ! "$BRANCH_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    print_error "Invalid branch name. Use only letters, numbers, hyphens, and underscores."
    exit 1
fi

# Check if branch already exists (local)
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    print_error "Branch '$BRANCH_NAME' already exists locally."
    echo "This script only creates NEW branches. Options:"
    echo "  1. Use a different branch name"
    echo "  2. Set up worktree manually: git worktree add ./notes $BRANCH_NAME"
    exit 1
fi

# Check if branch exists on remote
if git ls-remote --heads origin "$BRANCH_NAME" 2>/dev/null | grep -q "$BRANCH_NAME"; then
    print_error "Branch '$BRANCH_NAME' already exists on remote (origin)."
    echo "This script only creates NEW branches. Options:"
    echo "  1. Use a different branch name"
    echo "  2. Fetch and set up: git fetch origin $BRANCH_NAME && git worktree add ./notes $BRANCH_NAME"
    exit 1
fi

print_success "Branch name '$BRANCH_NAME' is available."
echo ""

# -------------------------------------------
# Prompt for worktree directory
# -------------------------------------------
read -p "Worktree directory [./notes]: " WORKTREE_DIR
WORKTREE_DIR="${WORKTREE_DIR:-./notes}"

# Normalize path
WORKTREE_DIR="${WORKTREE_DIR#./}"  # Remove leading ./
WORKTREE_PATH="$PROJECT_ROOT/$WORKTREE_DIR"

# Check if directory exists
if [ -d "$WORKTREE_PATH" ]; then
    print_error "Directory '$WORKTREE_DIR' already exists."
    echo "Please remove it or choose a different directory."
    exit 1
fi

print_success "Worktree directory: ./$WORKTREE_DIR"
echo ""

# -------------------------------------------
# Prompt for exclusion method
# -------------------------------------------
echo "Exclusion method determines how symlinks are hidden from git:"
echo "  1) .git/info/exclude - Local only, not tracked (personal setup)"
echo "  2) .gitignore        - Tracked, shared with team"
echo ""
read -p "Exclusion method [1/2, default: 1]: " EXCLUSION_CHOICE

case "$EXCLUSION_CHOICE" in
    2)
        EXCLUSION_METHOD="gitignore"
        EXCLUSION_FILE="$PROJECT_ROOT/.gitignore"
        print_info "Using .gitignore (team-shared)"
        ;;
    *)
        EXCLUSION_METHOD="exclude"
        EXCLUSION_FILE="$PROJECT_ROOT/.git/info/exclude"
        print_info "Using .git/info/exclude (local only)"
        ;;
esac
echo ""

# -------------------------------------------
# Prompt for moving existing .md files
# -------------------------------------------
MD_COUNT=$(find "$PROJECT_ROOT" \
    -name "*.md" \
    -not -path "$PROJECT_ROOT/README.md" \
    -not -path "$PROJECT_ROOT/node_modules/*" \
    -not -path "$PROJECT_ROOT/.git/*" \
    -not -path "*/node_modules/*" \
    2>/dev/null | wc -l | tr -d ' ')

if [ "$MD_COUNT" -gt 0 ]; then
    echo "Found $MD_COUNT markdown files (excluding root README.md)."
    read -p "Move existing .md files to notes and create symlinks? [y/N]: " MOVE_FILES
    MOVE_FILES="${MOVE_FILES:-n}"
else
    MOVE_FILES="n"
    print_info "No existing .md files found (excluding root README.md)."
fi
echo ""

# -------------------------------------------
# Confirm settings
# -------------------------------------------
echo "=========================================="
echo "  Configuration Summary"
echo "=========================================="
echo "  Branch name:      $BRANCH_NAME"
echo "  Worktree dir:     ./$WORKTREE_DIR"
echo "  Exclusion method: $EXCLUSION_METHOD"
echo "  Move .md files:   $MOVE_FILES"
echo "=========================================="
echo ""
read -p "Proceed with setup? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-y}"

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

echo ""

# -------------------------------------------
# Create orphan branch
# -------------------------------------------
print_info "Creating orphan branch '$BRANCH_NAME'..."

# Save current branch
CURRENT_BRANCH=$(git branch --show-current)

# Create orphan branch
git checkout --orphan "$BRANCH_NAME"
git rm -rf . > /dev/null 2>&1 || true
git clean -fd > /dev/null 2>&1 || true

# Create initial files
mkdir -p scripts
cat > README.md << 'DOCEOF'
# Documentation

This branch contains project documentation managed via git worktree.

See the main branch for code and setup instructions.
DOCEOF

# Create config file
cat > .notesrc << CONFIGEOF
{
  "branch": "$BRANCH_NAME",
  "worktree": "./$WORKTREE_DIR",
  "exclusion_method": "$EXCLUSION_METHOD",
  "exclude_root_readme": true
}
CONFIGEOF

# Create .gitignore for notes branch
cat > .gitignore << 'IGNOREEOF'
# Negate exclusions so files are tracked in notes branch
!**/README.md
!CLAUDE.md
!scripts/

# Ignore system files
.DS_Store
*.bak
.sync-notes-paths.tmp
IGNOREEOF

# Initial commit
git add -A
git commit -m "Initialize documentation branch"

# Switch back to original branch
git checkout "$CURRENT_BRANCH"

print_success "Created branch '$BRANCH_NAME' with initial commit."
echo ""

# -------------------------------------------
# Add worktree
# -------------------------------------------
print_info "Adding worktree at ./$WORKTREE_DIR..."
git worktree add "./$WORKTREE_DIR" "$BRANCH_NAME"
print_success "Worktree added."
echo ""

# -------------------------------------------
# Copy scripts to worktree
# -------------------------------------------
print_info "Copying management scripts..."
SCRIPT_SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_SRC_DIR/sync-notes.sh" "$WORKTREE_PATH/scripts/"
cp "$SCRIPT_SRC_DIR/combine-notes.sh" "$WORKTREE_PATH/scripts/"
cp "$SCRIPT_SRC_DIR/status-notes.sh" "$WORKTREE_PATH/scripts/"
cp "$SCRIPT_SRC_DIR/cleanup-notes.sh" "$WORKTREE_PATH/scripts/"
cp "$SCRIPT_SRC_DIR/teardown-notes.sh" "$WORKTREE_PATH/scripts/"
cp "$SCRIPT_SRC_DIR/notes-commit.sh" "$WORKTREE_PATH/scripts/"
cp "$SCRIPT_SRC_DIR/notes-push.sh" "$WORKTREE_PATH/scripts/"
cp "$SCRIPT_SRC_DIR/notes-pull.sh" "$WORKTREE_PATH/scripts/"
chmod +x "$WORKTREE_PATH/scripts/"*.sh
print_success "Scripts copied to $WORKTREE_DIR/scripts/"
echo ""

# -------------------------------------------
# Create scripts symlink
# -------------------------------------------
print_info "Creating scripts symlink..."
ln -sf "$WORKTREE_DIR/scripts" "$PROJECT_ROOT/scripts"
print_success "Created: scripts -> $WORKTREE_DIR/scripts"
echo ""

# -------------------------------------------
# Setup exclusions
# -------------------------------------------
print_info "Configuring exclusions in $EXCLUSION_FILE..."

EXCLUDE_MARKER="# >>> sync-notes managed entries >>>"
EXCLUDE_END="# <<< sync-notes managed entries <<<"

# Remove old managed entries if they exist
if grep -q "$EXCLUDE_MARKER" "$EXCLUSION_FILE" 2>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "/$EXCLUDE_MARKER/,/$EXCLUDE_END/d" "$EXCLUSION_FILE"
    else
        sed -i "/$EXCLUDE_MARKER/,/$EXCLUDE_END/d" "$EXCLUSION_FILE"
    fi
fi

# Add managed entries
{
    echo ""
    echo "$EXCLUDE_MARKER"
    echo "# Notes worktree (tracked in $BRANCH_NAME branch)"
    echo "/$WORKTREE_DIR/"
    echo "/scripts"

    if [ "$EXCLUSION_METHOD" = "gitignore" ]; then
        echo ""
        echo "# Documentation symlinks"
        echo "**/README.md"
        echo "CLAUDE.md"
        echo ""
        echo "# Exception: keep root README in main branch"
        echo "!/README.md"
    fi

    echo "$EXCLUDE_END"
} >> "$EXCLUSION_FILE"

print_success "Exclusions configured."
echo ""

# -------------------------------------------
# Commit notes branch changes
# -------------------------------------------
print_info "Committing scripts to notes branch..."
cd "$WORKTREE_PATH"
git add -A
git commit -m "Add sync and combine scripts" || true
cd "$PROJECT_ROOT"
print_success "Scripts committed."
echo ""

# -------------------------------------------
# Move existing .md files if requested
# -------------------------------------------
if [[ "$MOVE_FILES" =~ ^[Yy]$ ]]; then
    print_info "Running initial sync to move .md files..."
    "$WORKTREE_PATH/scripts/sync-notes.sh"
fi

# -------------------------------------------
# VSCode integration
# -------------------------------------------
echo ""
echo "VSCode Integration"
echo "------------------"
echo "Would you like to configure VSCode to hide the notes directory"
echo "from the file explorer and search results?"
echo ""
read -p "Configure VSCode? [y/N]: " VSCODE_CHOICE

if [[ "$VSCODE_CHOICE" =~ ^[Yy]$ ]]; then
    VSCODE_DIR="$PROJECT_ROOT/.vscode"
    VSCODE_SETTINGS="$VSCODE_DIR/settings.json"

    mkdir -p "$VSCODE_DIR"

    if [ -f "$VSCODE_SETTINGS" ]; then
        # Settings file exists - check if we need to add our settings
        if grep -q '"files.exclude"' "$VSCODE_SETTINGS" 2>/dev/null; then
            print_warning "VSCode settings.json already has files.exclude configured."
            echo "Please manually add these entries:"
            echo '  "files.exclude": { "'$WORKTREE_DIR'/": true }'
            echo '  "search.exclude": { "'$WORKTREE_DIR'/": true }'
        else
            # Try to add to existing JSON (basic approach)
            print_warning "VSCode settings.json exists but doesn't have files.exclude."
            echo "Please manually add these entries to .vscode/settings.json:"
            echo ""
            echo '  "files.exclude": {'
            echo '    "'$WORKTREE_DIR'/": true'
            echo '  },'
            echo '  "search.exclude": {'
            echo '    "'$WORKTREE_DIR'/": true'
            echo '  }'
        fi
    else
        # Create new settings file
        cat > "$VSCODE_SETTINGS" << VSCODEEOF
{
  "files.exclude": {
    "$WORKTREE_DIR/": true
  },
  "search.exclude": {
    "$WORKTREE_DIR/": true
  }
}
VSCODEEOF
        print_success "Created .vscode/settings.json"
        echo "  Notes directory will be hidden in VSCode explorer and search"
    fi
fi

# -------------------------------------------
# Done!
# -------------------------------------------
echo ""
echo "=========================================="
print_success "  Setup Complete!"
echo "=========================================="
echo ""
echo "Your notes worktree is ready at ./$WORKTREE_DIR"
echo ""
echo "Next steps:"
echo "  1. Edit documentation in ./$WORKTREE_DIR/ or via symlinks"
echo "  2. Run ./scripts/sync-notes.sh to sync new .md files"
echo "  3. Commit documentation:"
echo "     cd $WORKTREE_DIR && git add -A && git commit -m 'Update docs'"
echo "  4. Push notes branch:"
echo "     cd $WORKTREE_DIR && git push -u origin $BRANCH_NAME"
echo ""
if [ "$EXCLUSION_METHOD" = "gitignore" ]; then
    echo "  5. Commit .gitignore changes to main branch:"
    echo "     git add .gitignore && git commit -m 'Add notes worktree exclusions'"
fi
echo ""
