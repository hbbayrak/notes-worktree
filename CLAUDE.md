# CLAUDE.md

This file provides guidance for Claude when working with this codebase.

## Project Overview

**Notes Worktree** is a Claude Code plugin that manages documentation using git worktrees and symlinks. It keeps markdown files in a separate orphan branch while maintaining contextual access via symlinks in the main project.

## Repository Structure

```
notes-worktree/
├── README.md                    # Main documentation
├── .claude-plugin/
│   └── marketplace.json         # Plugin marketplace metadata
└── plugins/notes-worktree/
    ├── .claude-plugin/
    │   └── plugin.json          # Plugin definition
    └── skills/notes-worktree/
        ├── SKILL.md             # Skill instructions for Claude
        ├── references/
        │   └── setup-guide.md   # Detailed setup guide
        └── scripts/             # Bash utility scripts
            ├── _common.sh       # Shared utilities
            ├── init-notes-worktree.sh
            ├── sync-notes.sh
            ├── status-notes.sh
            ├── cleanup-notes.sh
            ├── teardown-notes.sh
            ├── notes-commit.sh
            ├── notes-push.sh
            ├── notes-pull.sh
            ├── combine-notes.sh
            └── manage-excludes.sh
```

## Key Scripts

All scripts are in `plugins/notes-worktree/skills/notes-worktree/scripts/`:

| Script | Purpose |
|--------|---------|
| `init-notes-worktree.sh` | Initialize notes worktree setup |
| `sync-notes.sh` | Bidirectional sync between worktree and symlinks |
| `status-notes.sh` | Health check and status report |
| `cleanup-notes.sh` | Fix dangling symlinks and stale exclusions |
| `teardown-notes.sh` | Remove the notes worktree setup |
| `notes-commit.sh` | Quick commit helper for notes branch |
| `notes-push.sh` | Push notes branch to remote |
| `notes-pull.sh` | Pull from remote and sync |
| `combine-notes.sh` | Generate combined markdown document |
| `manage-excludes.sh` | Add, remove, or list exclusion patterns |

## Development Commands

```bash
# Run any script directly
bash plugins/notes-worktree/skills/notes-worktree/scripts/<script-name>.sh

# Make scripts executable
chmod +x plugins/notes-worktree/skills/notes-worktree/scripts/*.sh
```

## Code Conventions

### Bash Scripts
- All scripts source `_common.sh` for shared utilities
- Use `set -euo pipefail` for strict error handling
- Logging functions: `log_info`, `log_warn`, `log_error`, `log_success`
- Color output via ANSI codes (with `NO_COLOR` support)
- Scripts are designed to be idempotent and safe to re-run

### Configuration
- Runtime config stored in `notes/.notesrc` (in the notes branch)
- Uses `.git/info/exclude` for local exclusions (default) or `.gitignore` for shared
- Relative symlinks maintain portability

### Key Functions in `_common.sh`
- `find_project_root` - Locate git repository root
- `load_config` - Load `.notesrc` configuration
- `log_*` functions - Consistent logging output

## Core Concepts

1. **Git Worktree**: The notes branch is checked out to a separate `notes/` directory
2. **Orphan Branch**: Notes branch has independent commit history
3. **Symlinks**: Relative symlinks (e.g., `docs/README.md → ../notes/docs/README.md`)
4. **Dual Exclusion**: Main branch excludes note files; notes branch tracks them

## Testing Changes

When modifying scripts:
1. Test in a disposable git repository first
2. Use `--dry-run` flag where available (e.g., `sync-notes.sh --dry-run`)
3. Run `status-notes.sh` to verify system health after changes

## Plugin Integration

- Plugin is registered via `plugin.json` and `marketplace.json`
- Skill definition in `SKILL.md` tells Claude how to use the scripts
- Users invoke via `/notes-worktree` skill command
