---
name: notes-worktree
description: Keeps a project's Markdown documentation in a separate git orphan branch (mounted as a worktree) and exposes it through relative symlinks in the main tree, so docs stay out of code diffs and PRs while remaining readable in place. Includes bash scripts to initialize the worktree, sync files bidirectionally, check status, manage exclusions, and tear the setup down.
when_to_use: Use when the user asks to "set up notes worktree", "create a documentation branch", "separate docs from code", "keep markdown in a separate branch", "symlink documentation", "move docs to a separate branch", or otherwise wants Markdown kept in a separate git branch while staying accessible via symlinks in the main project.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/*.sh:*)
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

When setting up a notes worktree, first check if the branch already exists, then either use existing configuration or ask the user.

### Step 1: Check for Existing Branch

Before asking any questions, check if the notes branch already exists:

1. Run the init script with just `--branch notes`
2. The script will automatically:
   - Check if branch exists locally
   - If not, check if branch exists on remote and fetch it
   - If branch exists, read configuration from `.notesrc` file
   - If branch doesn't exist, require all parameters

**If branch exists**: Skip all questions and proceed with setup using existing configuration.

**If branch is new**: Continue to Step 2 to gather configuration.

### Step 2: Ask for Configuration (New Branches Only)

Only ask these questions if the branch does NOT exist:

1. **Exclusion method**: How should symlinks be hidden from git?
   - `gitignore` - Shared with team via `.gitignore`
   - `exclude` - Local only via `.git/info/exclude`

2. **Move existing files**: Move existing `.md` files to notes and create symlinks?
   - Yes or No

3. **VSCode integration**: Configure VSCode to hide notes directory?
   - Yes or No

4. **Files or directories to keep in main**: Anything that should NOT move into
   the notes branch. Patterns may be filenames, globs, **or directory subtrees**.
   - Examples: `SKILL.md`, `*.generated.md`, `src/`, `docs/superpowers/`
   - Default: empty — but do not accept the default blindly; confirm it in Step 2a.

### Step 2a: Preview the Sweep Before Moving Anything (New Branches Only)

**Always do this before a `--move-files` setup.** The sweep moves *every* markdown
file (except the root `README.md`) into the notes branch, and that is easy to
regret for code-adjacent docs. Preview first:

```bash
${CLAUDE_SKILL_DIR}/scripts/init-notes-worktree.sh --dry-run [--exclude "..."]
```

This makes no changes. It lists the `.md` files that *would* move, grouped by
top-level directory, and flags directories that look code-adjacent with a
`⚠ consider --exclude` hint.

1. Show the preview to the user.
2. Ask explicitly: **"Which directories or files should stay in main?"** —
   pre-populating your suggestion with the directories the preview flagged.
3. Re-run `--dry-run --exclude "..."` to confirm the move/keep split looks right.
4. Only then run the real setup (Step 3) with the agreed `--exclude`.

### Step 3: Run Setup Script

The scripts are located in this skill's directory. Run the init script using the skill's scripts path:

**For existing branches** (config read from .notesrc):
```bash
${CLAUDE_SKILL_DIR}/scripts/init-notes-worktree.sh --branch notes
```

**For new branches** (all params required). Preview first with `--dry-run`
(Step 2a), then run the real setup:
```bash
# Preview only — no changes:
${CLAUDE_SKILL_DIR}/scripts/init-notes-worktree.sh --dry-run [--exclude "src/"]

# Real setup:
${CLAUDE_SKILL_DIR}/scripts/init-notes-worktree.sh \
  --branch notes \
  --dir ./notes \
  --exclusion <gitignore|exclude> \
  [--exclude "SKILL.md,src/,docs/superpowers/"] \
  [--move-files] \
  [--vscode]
```

`--exclude` patterns may be filenames, globs, or **directory subtrees**. Write a
subtree with a trailing `/` or `/**` (e.g. `src/`, `docs/superpowers/**`), or any
pattern containing a `/`. A bare token with no slash (e.g. `SKILL.md`) matches by
basename, as before.

`${CLAUDE_SKILL_DIR}` expands to this skill's directory at runtime; the scripts live in its `scripts/` subdirectory.

> **Confirm before teardown.** `teardown-notes.sh` removes the worktree and (unless `--keep-branch`) deletes the notes branch. Always confirm with the user before running it, and prefer `--dry-run` first.

### Example: Existing Branch Setup

```
Claude: I'll set up a notes worktree for documentation management.
Claude runs: ${CLAUDE_SKILL_DIR}/scripts/init-notes-worktree.sh --branch notes

Script output:
  Found existing local branch 'notes'
  Reading configuration from existing branch...
  Configuration loaded from .notesrc
  Setting up worktree from existing branch 'notes'...

Claude: Your notes worktree is set up! The configuration was loaded from the existing branch.
```

### Example: New Branch Setup

```
Claude: I'll set up a notes worktree for documentation management.
Claude runs: ${CLAUDE_SKILL_DIR}/scripts/init-notes-worktree.sh --branch notes

Script output:
  Branch name 'notes' is available.
  --dir required for new branch

Claude: The branch doesn't exist yet. Let me ask a few questions to configure it.
[AskUserQuestion: Exclusion method, Move files, VSCode integration, Keep-in-main]

User selects: gitignore, yes, yes

Claude previews the sweep before moving anything:
${CLAUDE_SKILL_DIR}/scripts/init-notes-worktree.sh --dry-run

Script output:
  Would MOVE into the notes branch (8 file(s)):
    docs/                3 file(s)
    src/                 5 file(s)   ⚠ code-adjacent — consider --exclude "src/"

Claude: src/ holds code-adjacent docs — shall I keep src/ in main?
User: yes, keep src/

Claude runs:
${CLAUDE_SKILL_DIR}/scripts/init-notes-worktree.sh \
  --branch notes --dir ./notes \
  --exclusion gitignore --exclude "src/" --move-files --vscode
```

For the full CLI reference and troubleshooting, see `references/setup-guide.md`.

## Key Concepts

### Git Worktree

A git worktree allows checking out a branch into a separate directory:

```
project/
├── .git/           # Main repo
├── src/            # Main branch content
├── client/
│   └── README.md   # Symlink → notes/client/README.md
└── notes/          # Worktree (notes branch)
    ├── .git        # Pointer to main .git
    ├── scripts     # Symlink → plugin scripts directory
    └── client/
        └── README.md  # Actual file
```

### Symlinks

Relative symlinks connect original locations to the notes directory:
- `client/README.md` → `../notes/client/README.md`
- Edit via symlink or directly in notes - same file

### Script Symlink

The `notes/scripts` symlink (inside the worktree) points directly to the plugin scripts directory. Scripts are NOT copied into the worktree - they remain in the plugin and are accessed via this symlink.

### Dual Exclusion Strategy

**Main branch exclusion** (`.git/info/exclude` or `.gitignore`):
```
/notes/
client/README.md
```

**Notes branch `.gitignore`** (negates exclusions):
```
/scripts
*.md
!/README.md
```

Only the root `README.md` is kept in the main branch; every other markdown file (including `CLAUDE.md`) lives in the notes branch and is reached via a symlink.

## Common Workflows

### Adding New Documentation

Create in notes directly:
```bash
mkdir -p notes/server/new-feature
echo "# New Feature" > notes/server/new-feature/README.md
./notes/scripts/sync-notes.sh  # Creates symlink
```

Or create normally and sync:
```bash
echo "# New Feature" > server/new-feature/README.md
./notes/scripts/sync-notes.sh  # Moves to notes, creates symlink
```

### Cloning a Project with Notes

The init script automatically detects and fetches existing remote branches:

```bash
# Option 1: Use the init script (recommended - handles everything)
${CLAUDE_SKILL_DIR}/scripts/init-notes-worktree.sh --branch notes

# Option 2: Manual setup
git worktree add ./notes notes
./notes/scripts/sync-notes.sh  # Creates all symlinks
```

### Updating Documentation

```bash
vim client/README.md  # Edit via symlink

./notes/scripts/notes-commit.sh "Update client documentation"
./notes/scripts/notes-push.sh
```

### Pulling Remote Changes

```bash
./notes/scripts/notes-pull.sh --auto-stash
```

For the full CLI reference and troubleshooting, see `references/setup-guide.md`.
