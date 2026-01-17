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
5. **VSCode integration** - hide notes from explorer/search

After setup, use these commands:

```bash
# Check status of notes setup
./scripts/status-notes.sh

# Sync new docs and create missing symlinks
./scripts/sync-notes.sh

# Sync with cleanup of dangling symlinks
./scripts/sync-notes.sh --cleanup

# Preview sync changes without making them
./scripts/sync-notes.sh --dry-run

# Watch for file changes and auto-sync
./scripts/sync-notes.sh --watch

# Quick commit and push
./scripts/notes-commit.sh "Add API documentation"
./scripts/notes-push.sh

# Pull remote changes and sync
./scripts/notes-pull.sh

# Generate combined documentation
./scripts/combine-notes.sh > all-docs.md

# Clean uninstall
./scripts/teardown-notes.sh
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
7. Optionally configures VSCode integration

### status-notes.sh

Health check and status report:
```bash
./scripts/status-notes.sh [OPTIONS]
  -v, --verbose    Show detailed file listings
  -q, --quiet      Show only errors and summary counts
```

Shows:
- Synced files (symlinks pointing to notes)
- Dangling symlinks (target missing in notes)
- Notes files without symlinks
- Stale exclusion entries
- Uncommitted changes in notes branch
- Unpushed commits

### sync-notes.sh

Bidirectional sync with multiple modes:
```bash
./scripts/sync-notes.sh [OPTIONS]
  --dry-run        Show what would happen without making changes
  --cleanup        Remove dangling symlinks and stale exclusions
  -v, --verbose    Show detailed output
  -q, --quiet      Show only errors
  --watch          Watch for file changes and auto-sync
  --no-interactive Skip interactive conflict prompts
```

Features:
- **Forward sync**: Moves `.md` files from main project to notes/, creates symlinks
- **Reverse sync**: Creates symlinks for files in notes/ lacking them in main project
- **Conflict resolution**: Interactive prompts to diff, keep main, keep notes, skip, or backup both
- **Watch mode**: Auto-sync on file changes (requires fswatch or inotifywait)
- Updates exclusion file based on config

Excludes: `node_modules/`, `.git/`, root `README.md`

### cleanup-notes.sh

Dedicated cleanup script:
```bash
./scripts/cleanup-notes.sh [OPTIONS]
  --dangling    Remove broken symlinks only
  --stale       Clean stale exclusion entries only
  --all         Fix everything (default)
  --dry-run     Show what would be done
  -v, --verbose Show detailed output
  -q, --quiet   Show only errors and summary
```

### teardown-notes.sh

Clean uninstall of the notes worktree setup:
```bash
./scripts/teardown-notes.sh [OPTIONS]
  --keep-branch    Don't delete the notes branch
  --keep-files     Convert symlinks back to real files
  --force          Skip confirmation prompts
  --dry-run        Show what would be done
```

Steps performed:
1. Optionally copy files from notes back to original locations
2. Remove all documentation symlinks
3. Remove scripts symlink
4. Clean exclusion file entries
5. Remove worktree
6. Optionally delete branch

### notes-commit.sh

Quick commit helper for notes branch:
```bash
./scripts/notes-commit.sh [MESSAGE]
# Default message: "Update documentation"
```

### notes-push.sh

Push notes branch to remote:
```bash
./scripts/notes-push.sh [REMOTE]
# Default remote: origin
```

Sets upstream automatically on first push.

### notes-pull.sh

Pull notes branch and sync symlinks:
```bash
./scripts/notes-pull.sh [REMOTE]
# Default remote: origin
```

Automatically stashes local changes if needed, then syncs symlinks after pull.

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

**Dangling symlinks after deleting files in notes:**
```bash
./scripts/status-notes.sh        # Check for issues
./scripts/sync-notes.sh --cleanup  # Fix them
```

**Symlink appears as file in git status:**
Check that the path is in exclusion file (`.git/info/exclude` or `.gitignore`).
Run `./scripts/sync-notes.sh` to update exclusions.

**Branch already exists error:**
The init script only creates new branches. Use existing setup or choose different name.

**Permission denied on scripts:**
Make scripts executable: `chmod +x notes/scripts/*.sh`

**Want to uninstall completely:**
```bash
./scripts/teardown-notes.sh  # Interactive teardown
./scripts/teardown-notes.sh --keep-files  # Keep docs as regular files
```

**Check overall health:**
```bash
./scripts/status-notes.sh -v  # Verbose status report
```

See `references/setup-guide.md` for detailed troubleshooting.
