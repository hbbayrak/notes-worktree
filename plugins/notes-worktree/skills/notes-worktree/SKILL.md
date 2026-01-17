---
name: notes-worktree
description: This skill should be used when the user asks to "set up notes worktree", "create documentation branch", "separate docs from code", "keep markdown in separate branch", "symlink documentation", "move docs to separate branch", or discusses keeping markdown files in a separate git branch while maintaining access via symlinks in the main project.
version: 2.0.0
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

## Setup Instructions for Claude

When setting up a notes worktree, use AskUserQuestion to gather configuration, then run the init script with the appropriate parameters.

### Step 1: Ask for Configuration

Use AskUserQuestion to gather these options:

1. **Exclusion method**: How should symlinks be hidden from git?
   - `gitignore` - Shared with team via `.gitignore`
   - `exclude` - Local only via `.git/info/exclude`

2. **Move existing files**: Move existing `.md` files to notes and create symlinks?
   - Yes or No

3. **VSCode integration**: Configure VSCode to hide notes directory?
   - Yes or No

4. **Exclude patterns**: Comma-separated list of file patterns to exclude from sync
   - Example: `SKILL.md,CHANGELOG.md,*.generated.md`
   - Default: empty (no exclusions)

### Step 2: Run Setup Script

The scripts are located in this skill's directory. Run the init script using the skill's scripts path:

```bash
<SKILL_SCRIPTS_DIR>/init-notes-worktree.sh \
  --branch notes \
  --dir ./notes \
  --exclusion <gitignore|exclude> \
  [--exclude "pattern1,pattern2"] \
  [--move-files] \
  [--vscode]
```

Where `<SKILL_SCRIPTS_DIR>` is the `scripts` subdirectory of this skill's base directory.

### Example Setup Flow

```
Claude: I'll set up a notes worktree for documentation management.
[AskUserQuestion: Exclusion method, Move files, VSCode integration, Exclude patterns]

User selects: gitignore, yes, yes, "SKILL.md"

Claude runs:
<skill_base_dir>/scripts/init-notes-worktree.sh \
  --branch notes --dir ./notes \
  --exclusion gitignore --exclude "SKILL.md" --move-files --vscode
```

## CLI Reference

All scripts are accessed via the `$PROJECT_ROOT/scripts` symlink which points to the plugin directory.

### init-notes-worktree.sh

Initialize notes worktree setup.

```bash
./scripts/init-notes-worktree.sh [OPTIONS]

Required:
  --branch NAME        Branch name for documentation (e.g., "notes")
  --dir PATH           Worktree directory path (e.g., "./notes")
  --exclusion METHOD   Exclusion method: 'gitignore' or 'exclude'

Optional:
  --move-files         Move existing .md files to notes and create symlinks
  --exclude PATTERNS   Comma-separated file patterns to exclude from sync
                       (e.g., "SKILL.md,CHANGELOG.md,*.generated.md")
  --vscode             Configure VSCode to hide notes directory
  -h, --help           Show help
```

### sync-notes.sh

Sync documentation files between main project and notes worktree.

```bash
./scripts/sync-notes.sh [OPTIONS]

Options:
  --dry-run            Show what would happen without making changes
  --cleanup            Remove dangling symlinks and stale exclusions
  -v, --verbose        Show detailed output
  -q, --quiet          Show only errors
  --watch              Watch for file changes and auto-sync
  --no-interactive     Skip interactive conflict prompts
  -h, --help           Show help
```

Features:
- **Forward sync**: Moves `.md` files from main project to notes, creates symlinks
- **Reverse sync**: Creates symlinks for files in notes lacking them in main
- **Auto-gitignore**: Non-README/CLAUDE files are automatically untracked when using gitignore exclusion

### status-notes.sh

Show status of notes worktree setup.

```bash
./scripts/status-notes.sh [OPTIONS]

Options:
  -v, --verbose    Show detailed file listings
  -q, --quiet      Show only errors and summary counts
  -h, --help       Show help
```

Shows:
- Synced files (symlinks pointing to notes)
- Dangling symlinks (target missing)
- Notes files without symlinks
- Stale exclusion entries
- Uncommitted/unpushed changes

### cleanup-notes.sh

Clean up notes worktree issues.

```bash
./scripts/cleanup-notes.sh [OPTIONS]

Options:
  --dangling       Remove broken symlinks only
  --stale          Clean stale exclusion entries only
  --all            Fix everything (default)
  --dry-run        Show what would be done
  -v, --verbose    Show detailed output
  -q, --quiet      Show only summary
  -h, --help       Show help
```

### teardown-notes.sh

Remove notes worktree setup and clean up.

```bash
./scripts/teardown-notes.sh [OPTIONS]

Options:
  --keep-branch    Don't delete the notes branch
  --keep-files     Convert symlinks back to real files
  --force          Skip confirmation prompts
  --dry-run        Show what would be done
  -h, --help       Show help
```

### notes-commit.sh

Quick commit helper for notes branch.

```bash
./scripts/notes-commit.sh [MESSAGE]

Arguments:
  MESSAGE    Commit message (default: "Update documentation")
```

### notes-push.sh

Push notes branch to remote.

```bash
./scripts/notes-push.sh [REMOTE]

Arguments:
  REMOTE    Remote name (default: "origin")
```

### notes-pull.sh

Pull notes branch from remote and sync symlinks.

```bash
./scripts/notes-pull.sh [OPTIONS] [REMOTE]

Arguments:
  REMOTE           Remote name (default: "origin")

Options:
  --auto-stash     Automatically stash local changes before pull
  --no-sync        Skip running sync after pull
  -h, --help       Show help
```

### combine-notes.sh

Generate combined markdown from all notes.

```bash
./scripts/combine-notes.sh > docs.md
./scripts/combine-notes.sh | pandoc -o docs.pdf
```

## Key Concepts

### Git Worktree

A git worktree allows checking out a branch into a separate directory:

```
project/
├── .git/           # Main repo
├── src/            # Main branch content
├── client/
│   └── README.md   # Symlink → notes/client/README.md
├── scripts         # Symlink → plugin scripts directory
└── notes/          # Worktree (notes branch)
    ├── .git        # Pointer to main .git
    └── client/
        └── README.md  # Actual file
```

### Symlinks

Relative symlinks connect original locations to the notes directory:
- `client/README.md` → `../notes/client/README.md`
- Edit via symlink or directly in notes - same file

### Script Symlink

The `/scripts` symlink points directly to the plugin scripts directory. Scripts are NOT copied into the worktree - they remain in the plugin and are accessed via this symlink.

### Dual Exclusion Strategy

**Main branch exclusion** (`.git/info/exclude` or `.gitignore`):
```
/notes/
/scripts
client/README.md
```

**Notes branch `.gitignore`** (negates exclusions):
```
/scripts
!**/README.md
!CLAUDE.md
```

## Common Workflows

### Adding New Documentation

Create in notes directly:
```bash
mkdir -p notes/server/new-feature
echo "# New Feature" > notes/server/new-feature/README.md
./scripts/sync-notes.sh  # Creates symlink
```

Or create normally and sync:
```bash
echo "# New Feature" > server/new-feature/README.md
./scripts/sync-notes.sh  # Moves to notes, creates symlink
```

### Cloning a Project with Notes

```bash
git worktree add ./notes notes
./scripts/sync-notes.sh  # Creates all symlinks
```

### Updating Documentation

```bash
vim client/README.md  # Edit via symlink

./scripts/notes-commit.sh "Update client documentation"
./scripts/notes-push.sh
```

### Pulling Remote Changes

```bash
./scripts/notes-pull.sh --auto-stash
```

## Troubleshooting

**Dangling symlinks after deleting files:**
```bash
./scripts/status-notes.sh        # Check for issues
./scripts/sync-notes.sh --cleanup  # Fix them
```

**Symlink appears in git status:**
Check that the path is in exclusion file. Run `./scripts/sync-notes.sh` to update exclusions.

**Permission denied on scripts:**
```bash
chmod +x ./scripts/*.sh
```

**Uninstall completely:**
```bash
./scripts/teardown-notes.sh  # Interactive teardown
./scripts/teardown-notes.sh --keep-files  # Keep docs as regular files
```
