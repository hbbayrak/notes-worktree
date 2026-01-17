#!/bin/bash
# Manage file exclusion patterns for notes-worktree
# Allows adding, removing, and listing patterns that are excluded from sync

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

# Initialize project root and load config
init_project_root
cd "$PROJECT_ROOT"
load_notes_config
verify_notes_worktree

# -------------------------------------------
# CLI Argument Parsing
# -------------------------------------------
COMMAND=""
PATTERNS=""
NO_COMMIT=false
QUIET=false

show_usage() {
    cat << 'EOF'
Usage: manage-excludes.sh <command> [OPTIONS] [patterns...]

Commands:
  list                 Show current exclusion patterns
  add <patterns>       Add patterns (comma-separated or multiple args)
  remove <patterns>    Remove patterns

Options:
  --no-commit          Don't auto-commit .notesrc changes
  -q, --quiet          Minimal output
  -h, --help           Show this help

Examples:
  manage-excludes.sh list
  manage-excludes.sh add "SKILL.md,CHANGELOG.md"
  manage-excludes.sh add SKILL.md CHANGELOG.md
  manage-excludes.sh remove "*.generated.md"
  manage-excludes.sh add "TODO.md" --no-commit
EOF
}

# Parse command first
if [[ $# -eq 0 ]]; then
    show_usage
    exit 1
fi

COMMAND="$1"
shift

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-commit) NO_COMMIT=true; shift ;;
        -q|--quiet) QUIET=true; shift ;;
        -h|--help) show_usage; exit 0 ;;
        -*)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            # Collect patterns (either comma-separated or space-separated)
            if [[ -n "$PATTERNS" ]]; then
                PATTERNS="$PATTERNS,$1"
            else
                PATTERNS="$1"
            fi
            shift
            ;;
    esac
done

# -------------------------------------------
# Helper Functions
# -------------------------------------------

CONFIG_FILE="$NOTES_ROOT/.notesrc"

# Parse current patterns from .notesrc into an array
get_current_patterns() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local raw_patterns
        raw_patterns=$(grep -o '"exclude_patterns"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 || echo "")
        echo "$raw_patterns"
    else
        echo ""
    fi
}

# Convert comma-separated string to sorted unique array
patterns_to_array() {
    local input="$1"
    # Split by comma, trim whitespace, remove empty, sort unique
    echo "$input" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | sort -u
}

# Convert array (newline-separated) back to comma-separated
array_to_patterns() {
    local input="$1"
    echo "$input" | paste -sd ',' -
}

# Update .notesrc with new patterns
update_config() {
    local new_patterns="$1"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    # Read current config
    local config_content
    config_content=$(cat "$CONFIG_FILE")

    # Use a temporary file for the replacement
    local temp_file
    temp_file=$(mktemp)

    # Replace exclude_patterns value (handle both empty and non-empty cases)
    if echo "$config_content" | grep -q '"exclude_patterns"'; then
        # Pattern exists, replace it
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -E 's/"exclude_patterns"[[:space:]]*:[[:space:]]*"[^"]*"/"exclude_patterns": "'"$new_patterns"'"/' "$CONFIG_FILE" > "$temp_file"
        else
            sed -E 's/"exclude_patterns"[[:space:]]*:[[:space:]]*"[^"]*"/"exclude_patterns": "'"$new_patterns"'"/' "$CONFIG_FILE" > "$temp_file"
        fi
        mv "$temp_file" "$CONFIG_FILE"
    else
        # Pattern doesn't exist, add it before the closing brace
        # This is a simple case - insert before last }
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' 's/}$/,\n  "exclude_patterns": "'"$new_patterns"'"\n}/' "$CONFIG_FILE"
        else
            sed -i 's/}$/,\n  "exclude_patterns": "'"$new_patterns"'"\n}/' "$CONFIG_FILE"
        fi
        rm -f "$temp_file" 2>/dev/null || true
    fi
}

# Commit changes to notes branch
commit_changes() {
    if $NO_COMMIT; then
        return
    fi

    cd "$NOTES_ROOT"

    if git diff --quiet .notesrc 2>/dev/null; then
        # No changes to commit
        return
    fi

    git add .notesrc
    git commit -m "Update exclude_patterns in .notesrc" --quiet

    if ! $QUIET; then
        log_success "Committed .notesrc changes to notes branch"
    fi
}

# -------------------------------------------
# Commands
# -------------------------------------------

cmd_list() {
    local current
    current=$(get_current_patterns)

    if [[ -z "$current" ]]; then
        if ! $QUIET; then
            echo "No exclusion patterns configured."
            echo ""
            echo "Add patterns with: manage-excludes.sh add \"pattern1,pattern2\""
        fi
        return
    fi

    if $QUIET; then
        echo "$current"
    else
        echo "Current exclusion patterns:"
        echo ""
        patterns_to_array "$current" | while read -r pattern; do
            echo "  - $pattern"
        done
        echo ""
        echo "These files are excluded from sync-notes.sh operations."
    fi
}

cmd_add() {
    if [[ -z "$PATTERNS" ]]; then
        print_error "No patterns specified"
        echo "Usage: manage-excludes.sh add <patterns>"
        exit 1
    fi

    local current new_array combined_array new_patterns added_count
    current=$(get_current_patterns)

    # Get arrays of current and new patterns
    local current_array new_input_array
    current_array=$(patterns_to_array "$current")
    new_input_array=$(patterns_to_array "$PATTERNS")

    # Combine and deduplicate
    combined_array=$(printf "%s\n%s" "$current_array" "$new_input_array" | grep -v '^$' | sort -u)

    # Convert back to comma-separated
    new_patterns=$(array_to_patterns "$combined_array")

    # Count how many were actually added (not duplicates)
    local current_count new_count
    current_count=$(echo "$current_array" | grep -v '^$' | wc -l | tr -d ' ')
    new_count=$(echo "$combined_array" | grep -v '^$' | wc -l | tr -d ' ')
    added_count=$((new_count - current_count))

    if [[ $added_count -eq 0 ]]; then
        if ! $QUIET; then
            echo "All patterns already exist. No changes made."
        fi
        return
    fi

    # Update config
    update_config "$new_patterns"

    if ! $QUIET; then
        log_success "Added $added_count pattern(s)"
        echo ""
        echo "Current patterns:"
        patterns_to_array "$new_patterns" | while read -r pattern; do
            echo "  - $pattern"
        done
    fi

    # Commit changes
    commit_changes

    if ! $QUIET; then
        echo ""
        echo "Run './$WORKTREE_DIR/scripts/sync-notes.sh' to apply changes."
    fi
}

cmd_remove() {
    if [[ -z "$PATTERNS" ]]; then
        print_error "No patterns specified"
        echo "Usage: manage-excludes.sh remove <patterns>"
        exit 1
    fi

    local current
    current=$(get_current_patterns)

    if [[ -z "$current" ]]; then
        if ! $QUIET; then
            echo "No patterns to remove. The exclusion list is empty."
        fi
        return
    fi

    # Get arrays
    local current_array remove_array
    current_array=$(patterns_to_array "$current")
    remove_array=$(patterns_to_array "$PATTERNS")

    # Remove patterns (filter out those in remove_array)
    local remaining_array
    remaining_array=$(echo "$current_array" | while read -r pattern; do
        local found=false
        echo "$remove_array" | while read -r remove_pattern; do
            if [[ "$pattern" == "$remove_pattern" ]]; then
                echo "FOUND"
                break
            fi
        done | grep -q "FOUND" || echo "$pattern"
    done)

    local new_patterns
    new_patterns=$(array_to_patterns "$remaining_array")

    # Count removed
    local current_count new_count removed_count
    current_count=$(echo "$current_array" | grep -v '^$' | wc -l | tr -d ' ')
    new_count=$(echo "$remaining_array" | grep -v '^$' | wc -l | tr -d ' ')
    removed_count=$((current_count - new_count))

    if [[ $removed_count -eq 0 ]]; then
        if ! $QUIET; then
            echo "No matching patterns found. No changes made."
        fi
        return
    fi

    # Update config
    update_config "$new_patterns"

    if ! $QUIET; then
        log_success "Removed $removed_count pattern(s)"
        if [[ -n "$new_patterns" ]]; then
            echo ""
            echo "Remaining patterns:"
            patterns_to_array "$new_patterns" | while read -r pattern; do
                echo "  - $pattern"
            done
        else
            echo "No patterns remaining."
        fi
    fi

    # Commit changes
    commit_changes

    if ! $QUIET; then
        echo ""
        echo "Run './$WORKTREE_DIR/scripts/sync-notes.sh' to apply changes."
    fi
}

# -------------------------------------------
# Main
# -------------------------------------------

case "$COMMAND" in
    list)
        cmd_list
        ;;
    add)
        cmd_add
        ;;
    remove)
        cmd_remove
        ;;
    -h|--help)
        show_usage
        exit 0
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac
