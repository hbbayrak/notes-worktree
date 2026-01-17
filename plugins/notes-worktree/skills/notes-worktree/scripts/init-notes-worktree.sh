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
# Helper Functions
# -------------------------------------------

# Check if branch exists locally
branch_exists_local() {
    local branch="$1"
    git show-ref --verify --quiet "refs/heads/$branch"
}

# Check if branch exists on remote
branch_exists_remote() {
    local branch="$1"
    git ls-remote --heads origin "$branch" 2>/dev/null | grep -q "$branch"
}

# Fetch remote branch to local
fetch_remote_branch() {
    local branch="$1"
    git fetch origin "$branch:$branch" 2>/dev/null
}

# Read config from branch's .notesrc file
read_config_from_branch() {
    local branch="$1"
    local config_content

    if ! config_content=$(git show "$branch:.notesrc" 2>/dev/null); then
        return 1
    fi

    # Parse JSON config (basic parsing with grep/sed)
    WORKTREE_DIR=$(echo "$config_content" | grep '"worktree"' | sed 's/.*"worktree"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | sed 's|^\./||')
    EXCLUSION_METHOD=$(echo "$config_content" | grep '"exclusion_method"' | sed 's/.*"exclusion_method"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    EXCLUDE_PATTERNS=$(echo "$config_content" | grep '"exclude_patterns"' | sed 's/.*"exclude_patterns"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    # Validate we got the required values
    if [[ -z "$WORKTREE_DIR" || -z "$EXCLUSION_METHOD" ]]; then
        return 1
    fi

    return 0
}

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

Required for NEW branches only (auto-detected from .notesrc for existing branches):
  --dir PATH           Worktree directory path
  --exclusion METHOD   Exclusion method: 'gitignore' or 'exclude'

Optional:
  --move-files         Move existing .md files to notes
  --exclude PATTERNS   Comma-separated file patterns to exclude from sync
                       (e.g., "SKILL.md,CHANGELOG.md,*.generated.md")
  --vscode             Configure VSCode integration
  -h, --help           Show this help

If the branch already exists (locally or on remote), configuration is read
from the branch's .notesrc file and questions are skipped.
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

# Validate branch name is always required
[[ -z "$BRANCH_NAME" ]] && { print_error "--branch required"; show_usage; exit 1; }

# Validate branch name format
if [[ ! "$BRANCH_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    print_error "Invalid branch name. Use only letters, numbers, hyphens, and underscores."
    exit 1
fi

# -------------------------------------------
# Check for Existing Branch
# -------------------------------------------
USE_EXISTING_BRANCH=false

if branch_exists_local "$BRANCH_NAME"; then
    USE_EXISTING_BRANCH=true
    print_info "Found existing local branch '$BRANCH_NAME'"
elif branch_exists_remote "$BRANCH_NAME"; then
    print_info "Found branch '$BRANCH_NAME' on remote, fetching..."
    if ! fetch_remote_branch "$BRANCH_NAME"; then
        print_error "Failed to fetch branch '$BRANCH_NAME' from remote."
        exit 1
    fi
    USE_EXISTING_BRANCH=true
    print_success "Fetched branch '$BRANCH_NAME' from remote."
fi

# For existing branches, read config from .notesrc
if $USE_EXISTING_BRANCH; then
    print_info "Reading configuration from existing branch..."
    if ! read_config_from_branch "$BRANCH_NAME"; then
        print_error "Could not read .notesrc from branch '$BRANCH_NAME'."
        echo "The branch may not have been created by this tool."
        echo "Please provide all parameters manually or use a different branch name."
        exit 1
    fi
    print_success "Configuration loaded from .notesrc"
    # For existing branches, don't move files by default
    MOVE_FILES=false
else
    # New branch - require all parameters
    [[ -z "$WORKTREE_DIR" ]] && { print_error "--dir required for new branch"; show_usage; exit 1; }
    [[ -z "$EXCLUSION_METHOD" ]] && { print_error "--exclusion required for new branch"; show_usage; exit 1; }
fi

# Validate exclusion method
[[ -n "$EXCLUSION_METHOD" && "$EXCLUSION_METHOD" != "gitignore" && "$EXCLUSION_METHOD" != "exclude" ]] && \
    { print_error "Invalid exclusion method: use 'gitignore' or 'exclude'"; exit 1; }

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

# -------------------------------------------
# Handle Worktree Already Exists
# -------------------------------------------
if [ -d "$WORKTREE_PATH" ]; then
    # Check if it's a git worktree
    if [ -f "$WORKTREE_PATH/.git" ]; then
        # It's a worktree - check which branch it's on
        WORKTREE_BRANCH=$(git -C "$WORKTREE_PATH" branch --show-current 2>/dev/null || echo "")
        if [ "$WORKTREE_BRANCH" = "$BRANCH_NAME" ]; then
            echo ""
            print_success "Notes worktree already set up correctly!"
            echo ""
            echo "Worktree: ./$WORKTREE_DIR"
            echo "Branch:   $BRANCH_NAME"
            echo ""
            echo "Nothing to do. Your notes worktree is ready."
            exit 0
        else
            print_error "Directory '$WORKTREE_DIR' is a worktree for branch '$WORKTREE_BRANCH', not '$BRANCH_NAME'."
            echo "Please remove it first or use a different directory."
            exit 1
        fi
    else
        # Directory exists but not a worktree
        print_error "Directory '$WORKTREE_DIR' already exists but is not a git worktree."
        echo "Please remove it or choose a different directory."
        exit 1
    fi
fi

if $USE_EXISTING_BRANCH; then
    print_info "Setting up worktree from existing branch '$BRANCH_NAME'..."
else
    print_success "Branch name '$BRANCH_NAME' is available."
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
# Create orphan branch (only for new branches)
# -------------------------------------------
if ! $USE_EXISTING_BRANCH; then
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
else
    print_info "Using existing branch '$BRANCH_NAME' (skipping branch creation)."
    echo ""
fi

# -------------------------------------------
# Add worktree
# -------------------------------------------
print_info "Adding worktree at ./$WORKTREE_DIR..."
git worktree add "./$WORKTREE_DIR" "$BRANCH_NAME"
print_success "Worktree added."
echo ""

# -------------------------------------------
# Create scripts symlink to plugin directory (inside worktree)
# -------------------------------------------
print_info "Creating scripts symlink inside worktree..."
ln -sf "$SCRIPT_DIR" "$PROJECT_ROOT/$WORKTREE_DIR/scripts"
print_success "Created: $WORKTREE_DIR/scripts -> $SCRIPT_DIR"
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

# Add managed entries - only add blank line if file doesn't end with one
{
    # Check if file exists and doesn't end with a blank line
    if [[ -s "$EXCLUSION_FILE" ]] && [[ -n "$(tail -c 1 "$EXCLUSION_FILE")" ]]; then
        echo ""  # File doesn't end with newline
    elif [[ -s "$EXCLUSION_FILE" ]] && [[ -n "$(tail -1 "$EXCLUSION_FILE")" ]]; then
        echo ""  # Last line has content, add blank line for separation
    fi
    echo "$EXCLUDE_MARKER"
    echo "# Notes worktree (tracked in $BRANCH_NAME branch)"
    echo "/$WORKTREE_DIR/"

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
        print_warning "Initial sync had issues. Run './$WORKTREE_DIR/scripts/sync-notes.sh' manually to retry."
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
echo "  2. Run ./$WORKTREE_DIR/scripts/sync-notes.sh to sync new .md files"
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
