#!/bin/bash
# Initialize a notes worktree for documentation management
# - Creates a new orphan branch for documentation
# - Sets up git worktree
# - Configures exclusions (local or shared)
# - Optionally syncs existing .md files

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

# Initialize project root
init_project_root
cd "$PROJECT_ROOT"

# -------------------------------------------
# CLI Argument Parsing
# -------------------------------------------
BRANCH_NAME=""
WORKTREE_DIR=""
EXCLUSION_METHOD=""
MOVE_FILES=false
VSCODE_CONFIG=false
EXCLUDE_PATTERNS=""

show_usage() {
    cat << 'EOF'
Usage: init-notes-worktree.sh [OPTIONS]

Required:
  --branch NAME        Branch name for documentation
  --dir PATH           Worktree directory path
  --exclusion METHOD   Exclusion method: 'gitignore' or 'exclude'

Optional:
  --move-files         Move existing .md files to notes
  --exclude PATTERNS   Comma-separated file patterns to exclude from sync
                       (e.g., "SKILL.md,CHANGELOG.md,*.generated.md")
  --vscode             Configure VSCode integration
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --branch) BRANCH_NAME="$2"; shift 2 ;;
        --dir) WORKTREE_DIR="$2"; shift 2 ;;
        --exclusion) EXCLUSION_METHOD="$2"; shift 2 ;;
        --move-files) MOVE_FILES=true; shift ;;
        --exclude) EXCLUDE_PATTERNS="$2"; shift 2 ;;
        --vscode) VSCODE_CONFIG=true; shift ;;
        -h|--help) show_usage; exit 0 ;;
        *) print_error "Unknown option: $1"; show_usage; exit 1 ;;
    esac
done

# Validate required params
[[ -z "$BRANCH_NAME" ]] && { print_error "--branch required"; show_usage; exit 1; }
[[ -z "$WORKTREE_DIR" ]] && { print_error "--dir required"; show_usage; exit 1; }
[[ -z "$EXCLUSION_METHOD" ]] && { print_error "--exclusion required"; show_usage; exit 1; }
[[ "$EXCLUSION_METHOD" != "gitignore" && "$EXCLUSION_METHOD" != "exclude" ]] && \
    { print_error "Invalid exclusion method: use 'gitignore' or 'exclude'"; exit 1; }

# Validate branch name
if [[ ! "$BRANCH_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    print_error "Invalid branch name. Use only letters, numbers, hyphens, and underscores."
    exit 1
fi

# Normalize worktree path
WORKTREE_DIR="${WORKTREE_DIR#./}"  # Remove leading ./
WORKTREE_PATH="$PROJECT_ROOT/$WORKTREE_DIR"

echo ""
echo "=========================================="
echo "  Notes Worktree Setup"
echo "=========================================="
echo ""
print_info "Project: $PROJECT_ROOT"
echo ""

# Check if branch already exists (local)
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    print_error "Branch '$BRANCH_NAME' already exists locally."
    echo "This script only creates NEW branches. Options:"
    echo "  1. Use a different branch name"
    echo "  2. Set up worktree manually: git worktree add ./$WORKTREE_DIR $BRANCH_NAME"
    exit 1
fi

# Check if branch exists on remote
if git ls-remote --heads origin "$BRANCH_NAME" 2>/dev/null | grep -q "$BRANCH_NAME"; then
    print_error "Branch '$BRANCH_NAME' already exists on remote (origin)."
    echo "This script only creates NEW branches. Options:"
    echo "  1. Use a different branch name"
    echo "  2. Fetch and set up: git fetch origin $BRANCH_NAME && git worktree add ./$WORKTREE_DIR $BRANCH_NAME"
    exit 1
fi

print_success "Branch name '$BRANCH_NAME' is available."
echo ""

# Check if directory exists
if [ -d "$WORKTREE_PATH" ]; then
    print_error "Directory '$WORKTREE_DIR' already exists."
    echo "Please remove it or choose a different directory."
    exit 1
fi

print_success "Worktree directory: ./$WORKTREE_DIR"
echo ""

# Set exclusion file based on method
if [ "$EXCLUSION_METHOD" = "gitignore" ]; then
    EXCLUSION_FILE="$PROJECT_ROOT/.gitignore"
    print_info "Using .gitignore (team-shared)"
else
    EXCLUSION_FILE="$PROJECT_ROOT/.git/info/exclude"
    print_info "Using .git/info/exclude (local only)"
fi
echo ""

# -------------------------------------------
# Configuration Summary
# -------------------------------------------
echo "=========================================="
echo "  Configuration Summary"
echo "=========================================="
echo "  Branch name:      $BRANCH_NAME"
echo "  Worktree dir:     ./$WORKTREE_DIR"
echo "  Exclusion method: $EXCLUSION_METHOD"
echo "  Move .md files:   $MOVE_FILES"
echo "  Exclude patterns: ${EXCLUDE_PATTERNS:-none}"
echo "  VSCode config:    $VSCODE_CONFIG"
echo "=========================================="
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
  "exclude_root_readme": true,
  "exclude_patterns": "$EXCLUDE_PATTERNS"
}
CONFIGEOF

# Create .gitignore for notes branch (scripts symlink is excluded)
cat > .gitignore << 'IGNOREEOF'
# Scripts symlink (points to plugin)
/scripts

# Negate exclusions so files are tracked in notes branch
!**/README.md
!CLAUDE.md

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
# Create scripts symlink to plugin directory
# -------------------------------------------
print_info "Creating scripts symlink to plugin..."
ln -sf "$SCRIPT_DIR" "$PROJECT_ROOT/scripts"
print_success "Created: scripts -> $SCRIPT_DIR"
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
# Move existing .md files if requested
# -------------------------------------------
if $MOVE_FILES; then
    print_info "Running initial sync to move .md files..."
    if ! "$SCRIPT_DIR/sync-notes.sh"; then
        print_warning "Initial sync had issues. Run './scripts/sync-notes.sh' manually to retry."
    fi
fi

# -------------------------------------------
# VSCode integration
# -------------------------------------------
if $VSCODE_CONFIG; then
    print_info "Configuring VSCode integration..."
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
    echo ""
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
