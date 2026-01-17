#!/bin/bash
# Combine all notes into a single markdown document
# - Generates pandoc-ready output with YAML front matter
# - Creates breadcrumb headings for each section
# - Shifts content headings to fit under their section level
# - Outputs to stdout for piping to file or pandoc

set -e

# -------------------------------------------
# Resolve paths
# -------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Handle case where script is in notes/scripts/
if [[ "$SCRIPT_DIR" == */notes/scripts ]] || [[ "$SCRIPT_DIR" == */*/scripts ]]; then
    NOTES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    PROJECT_ROOT="$(cd "$NOTES_ROOT/.." && pwd)"
else
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    NOTES_ROOT="$PROJECT_ROOT/notes"
fi

# Get project name from directory
PROJECT_NAME="$(basename "$PROJECT_ROOT")"

# -------------------------------------------
# Helper functions
# -------------------------------------------

# Shift heading levels by adding # characters
shift_headings() {
    local content="$1"
    local depth="$2"
    local prefix=""

    for ((i=0; i<depth; i++)); do
        prefix="${prefix}#"
    done

    echo "$content" | sed "s/^#/${prefix}#/g"
}

# Strip first H1 from content (title is in breadcrumb)
strip_first_h1() {
    local content="$1"
    echo "$content" | awk '
        BEGIN { found = 0 }
        /^#[^#]/ && !found { found = 1; next }
        { print }
    '
}

# Process a file and output with proper heading
# Usage: process_file "path" "breadcrumb" depth
process_file() {
    local file_path="$1"
    local breadcrumb="$2"
    local depth="$3"
    local heading_prefix=""

    for ((i=0; i<depth; i++)); do
        heading_prefix="${heading_prefix}#"
    done

    if [ ! -f "$file_path" ]; then
        echo "<!-- WARNING: File not found: $file_path -->" >&2
        return
    fi

    # Output section heading
    echo ""
    echo "${heading_prefix} ${breadcrumb}"
    echo ""

    # Read file, strip first H1, shift remaining headings
    local content
    content=$(cat "$file_path")
    content=$(strip_first_h1 "$content")

    # Shift by (depth - 1) levels
    local shift=$((depth - 1))
    content=$(shift_headings "$content" "$shift")

    echo "$content"
}

# Generate breadcrumb from path
# e.g., "client/src/modules/Auth" -> "Client > Src > Modules > Auth"
path_to_breadcrumb() {
    local path="$1"
    echo "$path" | sed 's/\// > /g' | sed 's/\b\(.\)/\u\1/g'
}

# Count files
count_files() {
    find "$NOTES_ROOT" -name "*.md" -not -name "*.bak" -not -path "*/.git/*" | wc -l | tr -d ' '
}

# Count lines
count_lines() {
    find "$NOTES_ROOT" -name "*.md" -not -name "*.bak" -not -path "*/.git/*" -exec cat {} \; 2>/dev/null | wc -l | tr -d ' '
}

# -------------------------------------------
# Generate document
# -------------------------------------------
generate_document() {
    local today
    today=$(date +%Y-%m-%d)
    local file_count
    file_count=$(count_files)
    local line_count
    line_count=$(count_lines)

    # YAML front matter for pandoc
    cat << EOF
---
title: "$PROJECT_NAME Documentation"
subtitle: "Combined Technical Documentation"
date: "$today"
toc: true
toc-depth: 4
documentclass: report
geometry: margin=1in
---

# $PROJECT_NAME Documentation

> **Generated:** $today | **Files:** $file_count | **Lines:** ~$line_count

---

EOF

    # Find all markdown files and process them
    local prev_section=""

    find "$NOTES_ROOT" \
        -name "*.md" \
        -not -name "*.bak" \
        -not -path "*/.git/*" \
        -not -name ".notesrc" \
        | sort | while read -r file; do

        # Skip internal files
        local basename
        basename=$(basename "$file")
        if [[ "$basename" == ".gitignore" ]] || [[ "$basename" == ".notesrc" ]]; then
            continue
        fi

        # Calculate relative path
        local rel_path="${file#$NOTES_ROOT/}"

        # Determine depth and section
        local depth
        depth=$(echo "$rel_path" | tr -cd '/' | wc -c)
        depth=$((depth + 2))  # Start at H2

        # Get directory for section grouping
        local dir_path
        dir_path=$(dirname "$rel_path")

        # Add section break for new top-level sections
        local top_section
        top_section=$(echo "$rel_path" | cut -d'/' -f1)
        if [ "$top_section" != "$prev_section" ] && [ -n "$prev_section" ]; then
            echo ""
            echo "---"
            echo ""
        fi
        prev_section="$top_section"

        # Generate breadcrumb
        local breadcrumb
        if [ "$rel_path" = "README.md" ]; then
            breadcrumb="Overview"
        elif [[ "$basename" == "README.md" ]]; then
            breadcrumb=$(path_to_breadcrumb "$dir_path")
        else
            local name_without_ext="${basename%.md}"
            if [ "$dir_path" = "." ]; then
                breadcrumb="$name_without_ext"
            else
                breadcrumb="$(path_to_breadcrumb "$dir_path") > $name_without_ext"
            fi
        fi

        process_file "$file" "$breadcrumb" "$depth"
    done

    # Footer
    echo ""
    echo "---"
    echo ""
    echo "*End of documentation*"
}

# -------------------------------------------
# Main
# -------------------------------------------
generate_document
