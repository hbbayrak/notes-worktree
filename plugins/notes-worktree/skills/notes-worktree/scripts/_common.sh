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
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
fi

# -------------------------------------------
# Logging functions
# -------------------------------------------
print_error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_info() { echo -e "${BLUE}$1${NC}"; }

# Verbosity-aware logging (requires QUIET and VERBOSE variables)
log_error()   { echo -e "${RED}ERROR: $1${NC}" >&2; return 0; }
log_success() { ${QUIET:-false} || echo -e "${GREEN}$1${NC}"; return 0; }
log_warning() { ${QUIET:-false} || echo -e "${YELLOW}$1${NC}"; return 0; }
log_info()    { ${QUIET:-false} || echo -e "${BLUE}$1${NC}"; return 0; }
log_verbose() { ${VERBOSE:-false} && echo -e "${CYAN}$1${NC}"; return 0; }
log_normal()  { ${QUIET:-false} || echo "$1"; return 0; }

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

    if [ ! -f "$config_file" ]; then
        # Worktree dir may be custom — find the notes worktree's .notesrc via git.
        local _wt
        while IFS= read -r _wt; do
            [ -n "$_wt" ] || continue
            if [ -f "$_wt/.notesrc" ]; then
                config_file="$_wt/.notesrc"
                break
            fi
        done < <(git -C "$PROJECT_ROOT" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
    fi

    if [ -f "$config_file" ]; then
        if command -v jq >/dev/null 2>&1; then
            # Parse JSON config with jq (fast path)
            EXCLUSION_METHOD=$(jq -r '.exclusion_method // ""' "$config_file")
            WORKTREE_DIR=$(jq -r '.worktree // ""' "$config_file")
            BRANCH_NAME=$(jq -r '.branch // ""' "$config_file")
            EXCLUDE_PATTERNS=$(jq -r '.exclude_patterns // ""' "$config_file")
        else
            # Parse JSON config (basic parsing without jq dependency)
            EXCLUSION_METHOD=$(grep -o '"exclusion_method"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | cut -d'"' -f4 || true)
            WORKTREE_DIR=$(grep -o '"worktree"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | cut -d'"' -f4 || true)
            BRANCH_NAME=$(grep -o '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | cut -d'"' -f4 || true)
            EXCLUDE_PATTERNS=$(grep -o '"exclude_patterns"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | cut -d'"' -f4 || true)
        fi
        WORKTREE_DIR="${WORKTREE_DIR#./}"  # Remove leading ./
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

# -------------------------------------------
# Keep the notes/scripts symlink pointed at the running plugin version
# -------------------------------------------
# init creates `notes/scripts` pointing at $SCRIPT_DIR, which is a version-pinned
# plugin cache path (.../<version>/...). After a plugin upgrade that target is
# stale (and eventually dangling once the old cache is garbage-collected), so a
# bare `./notes/scripts/*.sh` would keep running the OLD version. Because Claude
# always invokes the active version via ${CLAUDE_SKILL_DIR}, repairing the link to
# the currently-running $SCRIPT_DIR on each run keeps it pointed at live code.
# Requires NOTES_ROOT (set by load_notes_config). Sets SCRIPTS_SYMLINK_REPAIRED.
ensure_scripts_symlink() {
    SCRIPTS_SYMLINK_REPAIRED=false
    [ -n "${NOTES_ROOT:-}" ] && [ -d "$NOTES_ROOT" ] || return 0
    [ -d "$SCRIPT_DIR" ] || return 0

    local link="$NOTES_ROOT/scripts"
    local current=""
    if [ -L "$link" ]; then
        current="$(readlink "$link" 2>/dev/null || echo "")"
    elif [ -e "$link" ]; then
        # A real file/dir occupies the path — never clobber it
        return 0
    fi

    if [ "$current" != "$SCRIPT_DIR" ]; then
        if ln -sfn "$SCRIPT_DIR" "$link" 2>/dev/null; then
            SCRIPTS_SYMLINK_REPAIRED=true
            log_verbose "  Repaired notes/scripts symlink -> $SCRIPT_DIR"
        fi
    fi
    return 0
}

# Exclusion markers used in gitignore/exclude files
EXCLUDE_MARKER="# >>> sync-notes managed entries >>>"
EXCLUDE_END="# <<< sync-notes managed entries <<<"

# -------------------------------------------
# Exclude-pattern matching (path-aware)
# -------------------------------------------
# Trim leading/trailing whitespace from a single pattern.
_trim_pattern() {
    local p="$1"
    p="${p#"${p%%[![:space:]]*}"}"   # leading
    p="${p%"${p##*[![:space:]]}"}"   # trailing
    printf '%s' "$p"
}

# Decide whether a path (relative to the project/notes root, e.g.
# "docs/superpowers/guide.md") is excluded from sync by the configured
# EXCLUDE_PATTERNS. Supported pattern forms:
#   - basename glob, no slash:   SKILL.md, *.generated.md   (legacy behavior)
#   - directory subtree:         docs/superpowers/  or  docs/superpowers/**
#   - bare path with a slash:    docs/superpowers  (that path OR anything under it)
#   - path glob:                 docs/*.md
# Note: in path globs, '*' matches across '/' (bash glob semantics), so prefer
# "dir/" or "dir/**" when you mean "this whole subtree".
# Reads EXCLUDE_PATTERNS. Returns 0 (excluded) or 1 (not excluded).
notes_path_excluded() {
    local rel="$1"
    [ -n "${EXCLUDE_PATTERNS:-}" ] || return 1

    local base
    base="$(basename "$rel")"

    local raw pattern dir
    local -a _patterns
    IFS=',' read -ra _patterns <<< "$EXCLUDE_PATTERNS"
    for raw in "${_patterns[@]}"; do
        pattern="$(_trim_pattern "$raw")"
        [ -n "$pattern" ] || continue

        if [[ "$pattern" != */* ]]; then
            # No slash: legacy basename glob.
            # shellcheck disable=SC2053
            [[ "$base" == $pattern ]] && return 0
            continue
        fi

        if [[ "$pattern" == *'/**' ]]; then
            dir="${pattern%'/**'}"
            [[ "$rel" == "$dir" || "$rel" == "$dir"/* ]] && return 0
            continue
        fi

        if [[ "$pattern" == */ ]]; then
            dir="${pattern%/}"
            [[ "$rel" == "$dir"/* ]] && return 0
            continue
        fi

        if [[ "$pattern" == *[*?\[]* ]]; then
            # Path containing glob metacharacters: match the full relative path.
            # shellcheck disable=SC2053
            [[ "$rel" == $pattern ]] && return 0
            continue
        fi

        # Bare path with a slash and no glob: exact file OR directory subtree.
        [[ "$rel" == "$pattern" || "$rel" == "$pattern"/* ]] && return 0
    done
    return 1
}

# Convert an exclude pattern into the .gitignore negation line(s) that re-include
# the matching path(s) in the MAIN branch (which blanket-ignores *.md under the
# gitignore method). Directory subtrees must use /** so nested markdown is kept.
# Prints one or more "!..." lines on stdout.
to_gitignore_negation() {
    local pattern
    pattern="$(_trim_pattern "$1")"
    [ -n "$pattern" ] || return 0

    if [[ "$pattern" == *'/**' ]]; then
        printf '!%s\n' "$pattern"
    elif [[ "$pattern" == */ ]]; then
        printf '!%s**\n' "$pattern"                 # docs/x/ -> !docs/x/**
    elif [[ "$pattern" == */* && "$pattern" != *[*?\[]* ]]; then
        # Bare path with a slash, no glob: cover both file and subtree forms.
        printf '!%s\n' "$pattern"
        printf '!%s/**\n' "$pattern"
    else
        printf '!%s\n' "$pattern"                   # basename or glob: as-is
    fi
}
