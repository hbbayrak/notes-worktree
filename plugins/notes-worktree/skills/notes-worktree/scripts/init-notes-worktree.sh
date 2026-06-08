#!/bin/bash
# Initialize a notes worktree for documentation management
# - Creates a new orphan branch for documentation
# - Sets up git worktree
# - Configures exclusions (local or shared)
# - Optionally syncs existing .md files

set -euo pipefail

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
    git ls-remote --heads origin "$branch" 2>/dev/null | grep -q "refs/heads/$branch$"
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

    # Parse JSON config: prefer jq if available, otherwise fall back to grep/sed
    if command -v jq >/dev/null 2>&1; then
        WORKTREE_DIR=$(printf '%s' "$config_content" | jq -r '.worktree // ""' 2>/dev/null | sed 's|^\./||')
        EXCLUSION_METHOD=$(printf '%s' "$config_content" | jq -r '.exclusion_method // ""' 2>/dev/null)
        EXCLUDE_PATTERNS=$(printf '%s' "$config_content" | jq -r '.exclude_patterns // ""' 2>/dev/null)
    else
        WORKTREE_DIR=$(echo "$config_content" | grep '"worktree"' | sed 's/.*"worktree"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | sed 's|^\./||' || true)
        EXCLUSION_METHOD=$(echo "$config_content" | grep '"exclusion_method"' | sed 's/.*"exclusion_method"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)
        EXCLUDE_PATTERNS=$(echo "$config_content" | grep '"exclude_patterns"' | sed 's/.*"exclude_patterns"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)
    fi

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
DRY_RUN=false

show_usage() {
    cat << 'EOF'
Usage: init-notes-worktree.sh [OPTIONS]

Required:
  --branch NAME        Branch name for documentation

Required for NEW branches only (auto-detected from .notesrc for existing branches):
  --dir PATH           Worktree directory path
  --exclusion METHOD   Exclusion method: 'gitignore' or 'exclude'

Optional:
  --dry-run            Preview which .md files setup would move into the notes
                       branch (grouped by directory, flags code-adjacent trees),
                       then exit without making any changes
  --move-files         Move existing .md files to notes
  --exclude PATTERNS   Comma-separated patterns to keep in main (exclude from
                       sync). Supports filenames, globs, and directory subtrees:
                       "SKILL.md,*.generated.md,src/,docs/superpowers/"
  --vscode             Configure VSCode integration
  -h, --help           Show this help

If the branch already exists (locally or on remote), configuration is read
from the branch's .notesrc file and questions are skipped.
EOF
}

# Preview the forward-sync sweep without making any changes. Lists the markdown
# files that would be moved into the notes branch, grouped by top-level
# directory, and flags directories that look code-adjacent (likely "keep in
# main" candidates). Honors any patterns passed via --exclude.
preview_dry_run() {
    local preview_wt="${WORKTREE_DIR:-notes}"
    preview_wt="${preview_wt#./}"

    local tmp
    tmp="$(mktemp)"

    local f rel top status
    while IFS= read -r f; do
        [ -L "$f" ] && continue   # already a symlink; sync would skip it
        rel="${f#"$PROJECT_ROOT"/}"
        if [[ "$rel" == */* ]]; then top="${rel%%/*}"; else top="(root files)"; fi
        if notes_path_excluded "$rel"; then status="keep"; else status="move"; fi
        printf '%s\t%s\t%s\n' "$status" "$top" "$rel" >> "$tmp"
    done < <(find "$PROJECT_ROOT" \
        -name '*.md' \
        -not -path "$PROJECT_ROOT/README.md" \
        -not -path "$PROJECT_ROOT/.git/*" \
        -not -path "$PROJECT_ROOT/node_modules/*" \
        -not -path "*/node_modules/*" \
        -not -path "$PROJECT_ROOT/$preview_wt/*" \
        2>/dev/null | sort)

    echo ""
    echo "=========================================="
    echo "  Notes Worktree — Setup Preview (dry run)"
    echo "=========================================="
    print_info "Project: $PROJECT_ROOT"
    if [ -n "$EXCLUDE_PATTERNS" ]; then
        print_info "Exclude: $EXCLUDE_PATTERNS"
    fi
    echo ""

    if [ ! -s "$tmp" ]; then
        echo "No markdown files would be moved (nothing to sweep)."
        rm -f "$tmp"
        return 0
    fi

    local move_total
    move_total=$(awk -F'\t' '$1=="move"' "$tmp" | wc -l | tr -d ' ')

    if [ "$move_total" -eq 0 ]; then
        echo "Would move: nothing — all markdown is already excluded."
    else
        echo "Would MOVE into the notes branch ($move_total file(s)):"
        echo ""
        awk -F'\t' '$1=="move"{c[$2]++} END{for(k in c) printf "%s\t%d\n", k, c[k]}' "$tmp" \
            | sort | while IFS=$'\t' read -r top count; do
            if [ "$top" != "(root files)" ] && likely_code_dir "$top"; then
                printf "  %-28s %3d file(s)   \xe2\x9a\xa0 code-adjacent — consider --exclude \"%s/\"\n" "$top/" "$count" "$top"
            else
                printf "  %-28s %3d file(s)\n" "$top/" "$count"
            fi
        done
    fi

    if awk -F'\t' '$1=="keep"' "$tmp" | grep -q .; then
        echo ""
        echo "Would KEEP in main (already excluded):"
        echo ""
        awk -F'\t' '$1=="keep"{c[$2]++} END{for(k in c) printf "%s\t%d\n", k, c[k]}' "$tmp" \
            | sort | while IFS=$'\t' read -r top count; do
            printf "  %-28s %3d file(s)\n" "$top/" "$count"
        done
    fi

    echo ""
    echo "Root README.md is always kept in main."
    echo ""
    echo "Re-run with --exclude \"dir/,other/\" to keep directories in main,"
    echo "or proceed (without --dry-run) to set up and move the rest."
    echo ""

    rm -f "$tmp"
    return 0
}

# Heuristic: does this top-level directory look like it holds code (so its
# markdown is probably code-adjacent and better left in main)? Matches common
# code directory names, or any tree that contains source files.
likely_code_dir() {
    local top="$1"
    case "$top" in
        src|lib|libs|pkg|packages|internal|vendor|app|apps|cmd|test|tests|spec|examples|example)
            return 0 ;;
    esac
    if find "$PROJECT_ROOT/$top" -type f \( \
            -name '*.js' -o -name '*.ts' -o -name '*.jsx' -o -name '*.tsx' \
            -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.java' \
            -o -name '*.rb' -o -name '*.php' -o -name '*.c' -o -name '*.h' \
            -o -name '*.cpp' -o -name '*.cc' -o -name '*.cs' -o -name '*.swift' \
            -o -name '*.kt' -o -name '*.scala' -o -name '*.sh' \
            \) -print -quit 2>/dev/null | grep -q .; then
        return 0
    fi
    return 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --branch) BRANCH_NAME="$2"; shift 2 ;;
        --dir) WORKTREE_DIR="$2"; shift 2 ;;
        --exclusion) EXCLUSION_METHOD="$2"; shift 2 ;;
        --move-files) MOVE_FILES=true; shift ;;
        --exclude) EXCLUDE_PATTERNS="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --vscode) VSCODE_CONFIG=true; shift ;;
        -h|--help) show_usage; exit 0 ;;
        *) print_error "Unknown option: $1"; show_usage; exit 1 ;;
    esac
done

# Preview mode: show what the sweep would move and exit without any changes.
# Intentionally does not require --branch/--dir so it can run on a virgin repo.
if $DRY_RUN; then
    preview_dry_run
    exit 0
fi

# Validate branch name is always required
[[ -z "$BRANCH_NAME" ]] && { print_error "--branch required"; show_usage; exit 1; }

# Validate branch name format
if [[ ! "$BRANCH_NAME" =~ ^[a-zA-Z0-9_/.-]+$ ]]; then
    print_error "Invalid branch name. Use only letters, numbers, hyphens, underscores, slashes, and dots."
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
            # Refresh the scripts symlink in case the plugin was upgraded since setup
            NOTES_ROOT="$WORKTREE_PATH"
            ensure_scripts_symlink
            echo ""
            print_success "Notes worktree already set up correctly!"
            echo ""
            echo "Worktree: ./$WORKTREE_DIR"
            echo "Branch:   $BRANCH_NAME"
            if ${SCRIPTS_SYMLINK_REPAIRED:-false}; then
                echo ""
                echo "(Refreshed notes/scripts symlink to the current plugin version.)"
            fi
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

    # Save current ref so we can return here afterwards.
    # On a detached HEAD, --show-current is empty, so fall back to the
    # abbreviated ref name (or the raw commit SHA) to make checkout-back work.
    CURRENT_BRANCH=$(git branch --show-current)
    if [[ -z "$CURRENT_BRANCH" ]]; then
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [[ -z "$CURRENT_BRANCH" || "$CURRENT_BRANCH" == "HEAD" ]]; then
            CURRENT_BRANCH=$(git rev-parse HEAD)
        fi
    fi

    # Create orphan branch
    git checkout --orphan "$BRANCH_NAME"
    git rm -rf . > /dev/null 2>&1 || true
    git clean -fd > /dev/null 2>&1 || true

    # Create initial files
    cat > README.md << 'DOCEOF'
This branch contains project documentation managed via git worktree.
DOCEOF

    # Create config file. Build with jq when available so that patterns
    # containing quotes or backslashes can't corrupt the JSON; otherwise
    # fall back to a heredoc.
    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --arg branch "$BRANCH_NAME" \
            --arg worktree "./$WORKTREE_DIR" \
            --arg method "$EXCLUSION_METHOD" \
            --arg patterns "$EXCLUDE_PATTERNS" \
            '{branch:$branch, worktree:$worktree, exclusion_method:$method, exclude_root_readme:true, exclude_patterns:$patterns}' \
            > .notesrc
    else
        cat > .notesrc << CONFIGEOF
{
  "branch": "$BRANCH_NAME",
  "worktree": "./$WORKTREE_DIR",
  "exclusion_method": "$EXCLUSION_METHOD",
  "exclude_root_readme": true,
  "exclude_patterns": "$EXCLUDE_PATTERNS"
}
CONFIGEOF
    fi

    # Create .gitignore for notes branch (scripts symlink is excluded)
    {
        echo "# Scripts symlink (points to plugin)"
        echo "/scripts"
        echo ""
        echo "# Negate exclusions so files are tracked in notes branch"
        echo "!*.md"
        echo ""
        # Add exclusion patterns (files to keep in main, not tracked in notes)
        if [ -n "$EXCLUDE_PATTERNS" ]; then
            echo "# Files excluded from notes (kept in main branch)"
            IFS=',' read -ra PATTERNS <<< "$EXCLUDE_PATTERNS"
            for pattern in "${PATTERNS[@]}"; do
                pattern=$(echo "$pattern" | xargs)  # trim whitespace
                echo "$pattern"
            done
            echo ""
        fi
        echo "# Ignore system files"
        echo ".DS_Store"
        echo "*.bak"
        echo ".sync-notes-paths.tmp"
    } > .gitignore

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

# Set up remote tracking and sync if using existing branch from remote
if $USE_EXISTING_BRANCH && branch_exists_remote "$BRANCH_NAME"; then
    # Check if upstream is already set
    UPSTREAM=$(git -C "$PROJECT_ROOT/$WORKTREE_DIR" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")
    if [[ -z "$UPSTREAM" ]]; then
        print_info "Setting up remote tracking for '$BRANCH_NAME'..."
        git -C "$PROJECT_ROOT/$WORKTREE_DIR" branch --set-upstream-to="origin/$BRANCH_NAME" "$BRANCH_NAME"
        print_success "Remote tracking configured."
    fi

    # Pull latest changes
    print_info "Syncing with remote..."
    if git -C "$PROJECT_ROOT/$WORKTREE_DIR" pull --ff-only 2>/dev/null; then
        print_success "Synced with remote."
    else
        print_warning "Could not fast-forward. You may need to manually pull/merge."
    fi
fi
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

# Remove old managed entries if they exist. Use literal-line matching via awk
# so the marker text (which contains regex metacharacters like >>> / <<<) is
# never interpreted as a pattern.
if grep -qF "$EXCLUDE_MARKER" "$EXCLUSION_FILE" 2>/dev/null; then
    awk -v start="$EXCLUDE_MARKER" -v end="$EXCLUDE_END" '
        $0 == start { skip=1 }
        skip { if ($0 == end) skip=0; next }
        { print }
    ' "$EXCLUSION_FILE" > "$EXCLUSION_FILE.tmp" && mv "$EXCLUSION_FILE.tmp" "$EXCLUSION_FILE"
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
        echo "# Documentation symlinks (all markdown files)"
        echo "*.md"
        echo ""
        echo "# Exceptions: keep these in main branch"
        echo "!/README.md"

        # Add exclusion patterns as exceptions (kept in main branch).
        # Directory subtrees are normalized to "!dir/**" so nested markdown is
        # re-included under the blanket "*.md" ignore.
        if [ -n "$EXCLUDE_PATTERNS" ]; then
            IFS=',' read -ra PATTERNS <<< "$EXCLUDE_PATTERNS"
            for pattern in "${PATTERNS[@]}"; do
                to_gitignore_negation "$pattern"
            done
        fi
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
# Materialize symlinks for an existing branch (clone / onboarding path)
# -------------------------------------------
# For an existing branch the root-level symlinks (e.g. CLAUDE.md -> notes/CLAUDE.md)
# are not committed in either branch, so a freshly-mounted worktree has NO symlinks
# until a reverse sync creates them -- project instructions wouldn't auto-load and
# doc links would be broken. We run a symlinks-only reverse sync (NOT the full
# forward sweep, which would move a teammate's own stray code-tree .md files into
# the notes branch) so onboarding completes in a single step.
if $USE_EXISTING_BRANCH; then
    print_info "Creating documentation symlinks (reverse sync)..."
    if "$SCRIPT_DIR/sync-notes.sh" --reverse-only --quiet; then
        print_success "Documentation symlinks created."
    else
        print_warning "Symlink creation had issues. Run './$WORKTREE_DIR/scripts/sync-notes.sh --reverse-only' manually to retry."
    fi
    echo ""
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
if $USE_EXISTING_BRANCH; then
    # Existing-branch / clone path: the symlinks were just materialized, so the
    # project is already usable. No initial sweep or first commit is required.
    echo "Documentation symlinks are in place -- the project is ready to use."
    echo ""
    echo "Next steps:"
    echo "  - Edit documentation in ./$WORKTREE_DIR/ or via the symlinks"
    echo "  - After adding new .md files:  ./$WORKTREE_DIR/scripts/sync-notes.sh"
    echo "  - Commit & push docs:"
    echo "      cd $WORKTREE_DIR && git add -A && git commit -m 'Update docs' && git push"
else
    echo "Next steps:"
    echo "  1. Edit documentation in ./$WORKTREE_DIR/ or via symlinks"
    echo "  2. Run ./$WORKTREE_DIR/scripts/sync-notes.sh to sync new .md files"
    echo "  3. Commit documentation:"
    echo "     cd $WORKTREE_DIR && git add -A && git commit -m 'Update docs'"
    echo "  4. Push notes branch:"
    echo "     cd $WORKTREE_DIR && git push -u origin $BRANCH_NAME"
    if [ "$EXCLUSION_METHOD" = "gitignore" ]; then
        echo ""
        echo "  5. Commit .gitignore changes to main branch:"
        echo "     git add .gitignore && git commit -m 'Add notes worktree exclusions'"
    fi
fi
echo ""
