# Notes Worktree Plugin

A Claude Code plugin that helps you set up a documentation management system using git worktrees.

## What It Does

This plugin implements a pattern where markdown documentation files live in a separate git branch, accessed via symlinks in the main project. This keeps your main branch clean from documentation commits while keeping docs accessible in their logical locations.

**Benefits:**
- Documentation has its own commit history
- No documentation changes in code PRs
- Docs remain contextually accessible via symlinks
- Teams can maintain docs independently from code

## Installation

```bash
claude plugins add ~/Code/notes-worktree
```

Or clone and add:
```bash
git clone <repo-url> ~/Code/notes-worktree
claude plugins add ~/Code/notes-worktree
```

## Usage

### Ask Claude

Simply ask Claude to set up notes worktree:

> "Set up a notes worktree for this project"
> "Separate my documentation into a different branch"
> "Create a docs branch with symlinks"

### Manual Setup

Run the init script in any git project:

```bash
./path/to/notes-worktree/skills/notes-worktree/scripts/init-notes-worktree.sh
```

The script will interactively prompt for:
1. Branch name (default: `notes`)
2. Worktree directory (default: `./notes`)
3. Exclusion method: local (`.git/info/exclude`) or shared (`.gitignore`)
4. Whether to move existing `.md` files

### After Setup

```bash
# Sync new documentation files
./scripts/sync-notes.sh

# Generate combined documentation
./scripts/combine-notes.sh > all-docs.md
./scripts/combine-notes.sh | pandoc -o docs.pdf

# Commit documentation changes
cd notes
git add -A
git commit -m "Update documentation"
git push
```

## How It Works

```
project/
├── client/
│   └── README.md      # Symlink → notes/client/README.md
├── server/
│   └── README.md      # Symlink → notes/server/README.md
├── notes/             # Worktree (notes branch)
│   ├── client/
│   │   └── README.md  # Actual file
│   └── server/
│       └── README.md  # Actual file
└── scripts → notes/scripts
```

- **Main branch**: Contains code + symlinks to docs
- **Notes branch**: Contains actual documentation files
- **Symlinks**: Make docs accessible in expected locations

## Scripts

| Script | Purpose |
|--------|---------|
| `init-notes-worktree.sh` | Interactive setup for new projects |
| `sync-notes.sh` | Bidirectional sync with --dry-run, --cleanup, --watch |
| `status-notes.sh` | Health check and sync status report |
| `cleanup-notes.sh` | Fix dangling symlinks and stale exclusions |
| `teardown-notes.sh` | Clean uninstall of the setup |
| `notes-commit.sh` | Quick commit helper for notes branch |
| `notes-push.sh` | Push notes branch to remote |
| `notes-pull.sh` | Pull and sync symlinks |
| `combine-notes.sh` | Generate combined markdown document |

## Configuration

Settings are stored in `notes/.notesrc`:

```json
{
  "branch": "notes",
  "worktree": "./notes",
  "exclusion_method": "gitignore",
  "exclude_root_readme": true
}
```

## Exclusion Methods

### Local Only (`.git/info/exclude`)
- Not tracked in git
- Each developer runs setup locally
- Best for personal use or gradual adoption

### Team Shared (`.gitignore`)
- Tracked and shared with team
- Everyone gets same setup automatically
- Root `README.md` is preserved in main branch

## License

MIT
