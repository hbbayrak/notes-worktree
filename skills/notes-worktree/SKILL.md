---
name: notes-worktree
description: This skill should be used when the user asks to "set up notes worktree", "create documentation branch", "separate docs from code", "keep markdown in separate branch", "symlink documentation", "move docs to separate branch", or discusses keeping markdown files in a separate git branch while maintaining access via symlinks in the main project.
version: 1.0.0
---

# Notes Worktree Pattern

A documentation management system that keeps markdown files in a separate git branch while maintaining contextual access via symlinks. This keeps the main branch clean from documentation commits while documentation remains accessible in its logical locations.

## Overview

The notes worktree pattern solves a common problem: documentation clutters git history and code reviews. By storing `.md` files in a separate orphan branch mounted as a git worktree, documentation:

- Has its own commit history
- Does not appear in main branch diffs or PRs
- Remains accessible via symlinks in expected locations
- Can be maintained by different contributors

## When to Use

Use this pattern when:
- Documentation changes frequently and clutters PRs
- Multiple teams contribute to docs vs code
- The codebase has many README files per folder
- Keeping the main branch focused on code changes

## Quick Start

Run the interactive setup:

```bash
./scripts/init-notes-worktree.sh
```

The script prompts for:
1. **Branch name** (default: `notes`) - must not exist
2. **Worktree directory** (default: `./notes`)
3. **Exclusion method**: `.git/info/exclude` (local) or `.gitignore` (team)
4. **Whether to move existing .md files**

After setup, use these commands:

```bash
# Sync new docs and create missing symlinks
./scripts/sync-notes.sh

# Generate combined documentation
./scripts/combine-notes.sh > all-docs.md

# Commit documentation changes
cd notes && git add -A && git commit -m "Update docs"
```

## Key Concepts

### Git Worktree

A git worktree allows checking out a branch into a separate directory. The `notes` directory contains the `notes` branch while the parent directory contains your main branch:

```
project/
├── .git/           # Main repo
├── src/            # Main branch content
├── client/
│   └── README.md   # Symlink → notes/client/README.md
└── notes/          # Worktree (notes branch)
    ├── .git        # Pointer to main .git
    └── client/
        └── README.md  # Actual file
```

### Symlinks

Relative symlinks connect original locations to the notes directory:
- `client/README.md` → `../notes/client/README.md`
- Edit via symlink or directly in notes - same file

### Dual Exclusion Strategy

To keep both branches clean, exclusions work at two levels:

**Main branch exclusion** (`.git/info/exclude` or `.gitignore`):
```
/notes/
client/README.md
server/README.md
```

**Notes branch `.gitignore`** (negates the exclusions):
```
!**/README.md
!CLAUDE.md
```

This ensures:
- Main branch ignores symlinks and notes directory
- Notes branch tracks the actual files

### Exclusion Methods

**Local only (`.git/info/exclude`):**
- Not tracked in git
- Each developer runs setup locally
- Best for personal workflow or gradual adoption

**Team shared (`.gitignore`):**
- Tracked and shared with team
- Everyone gets same exclusions automatically
- Root `README.md` is excepted (not symlinked)

## Script Reference

### init-notes-worktree.sh

Interactive setup that:
1. Validates branch does not exist (local or remote)
2. Creates orphan branch
3. Adds worktree
4. Configures exclusion method
5. Saves config to `notes/.notesrc`
6. Optionally runs initial sync

### sync-notes.sh

Bidirectional sync that:
- **Forward**: Moves `.md` files from main project to notes/, creates symlinks
- **Reverse**: Creates symlinks for files in notes/ lacking them in main project
- Updates exclusion file based on config
- Handles conflicts (backs up differing files)

Excludes: `node_modules/`, `.git/`, root `README.md`

### combine-notes.sh

Generates combined markdown:
- Scans notes/ for all `.md` files
- Creates section headings with breadcrumbs
- Shifts heading levels appropriately
- Outputs to stdout for piping

Usage:
```bash
./scripts/combine-notes.sh > docs.md
./scripts/combine-notes.sh | pandoc -o docs.pdf
```

## Directory Structure

After setup:
```
project/
├── notes/                    # Worktree (notes branch)
│   ├── .git                  # Worktree pointer
│   ├── .gitignore            # Negates exclusions
│   ├── .notesrc              # Config (JSON)
│   └── [mirrored structure]  # .md files here
├── scripts → notes/scripts   # Symlink to scripts
└── [code files]              # Main branch
```

## Common Workflows

### Adding New Documentation

Create the file in notes/ directly:
```bash
mkdir -p notes/server/new-feature
echo "# New Feature" > notes/server/new-feature/README.md
./scripts/sync-notes.sh  # Creates symlink
```

Or create normally and sync:
```bash
echo "# New Feature" > server/new-feature/README.md
./scripts/sync-notes.sh  # Moves to notes/, creates symlink
```

### Cloning a Project with Notes

After cloning, set up the worktree and sync:
```bash
git worktree add ./notes notes
./scripts/sync-notes.sh  # Creates all symlinks
```

### Updating Documentation

Edit via symlink or directly - changes go to notes branch:
```bash
vim client/README.md  # Edit via symlink
# or
vim notes/client/README.md  # Edit directly

cd notes
git add -A
git commit -m "Update client documentation"
git push
```

## Troubleshooting

**Symlink appears as file in git status:**
Check that the path is in exclusion file (`.git/info/exclude` or `.gitignore`).

**Branch already exists error:**
The init script only creates new branches. Use existing setup or choose different name.

**Permission denied on scripts:**
Make scripts executable: `chmod +x notes/scripts/*.sh`

See `references/setup-guide.md` for detailed troubleshooting.
