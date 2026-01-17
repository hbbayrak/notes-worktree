# Notes Worktree Setup Guide

This guide provides detailed information about the notes worktree pattern, including manual setup steps, the dual exclusion strategy, and troubleshooting.

## Understanding Git Worktrees

A git worktree is a linked working tree attached to a repository. Unlike branches that exist in the same directory, worktrees allow you to have multiple branches checked out simultaneously in different directories.

### How It Works

```
project/
├── .git/                     # Main repository
│   └── worktrees/
│       └── notes/            # Worktree metadata
├── [main branch files]
└── notes/                    # Worktree directory
    ├── .git                  # File pointing to .git/worktrees/notes
    └── [notes branch files]
```

The `notes/.git` file is not a directory but a text file containing:
```
gitdir: /path/to/project/.git/worktrees/notes
```

This tells git where to find the repository data for this worktree.

## Manual Setup Steps

If you prefer to set up manually instead of using `init-notes-worktree.sh`:

### Step 1: Create Orphan Branch

An orphan branch has no parent commits - it starts with empty history:

```bash
# Create and switch to orphan branch
git checkout --orphan notes

# Remove all files from staging (they came from previous branch)
git rm -rf .

# Create initial commit
echo "# Documentation" > README.md
git add README.md
git commit -m "Initialize notes branch"

# Switch back to main branch
git checkout main
```

### Step 2: Add Worktree

```bash
# Add the notes branch as a worktree in ./notes directory
git worktree add ./notes notes
```

### Step 3: Configure Exclusions

Choose one method:

**Option A: Local Only (.git/info/exclude)**

Edit `.git/info/exclude`:
```
# Notes worktree
/notes/
/scripts

# Documentation symlinks (add as you create them)
client/README.md
server/README.md
CLAUDE.md
```

**Option B: Team Shared (.gitignore)**

Add to `.gitignore`:
```
# Notes worktree
/notes/
/scripts

# Documentation symlinks
**/README.md
CLAUDE.md

# Exception: keep root README in main branch
!/README.md
```

### Step 4: Create Notes .gitignore

In `notes/.gitignore`:
```
# Negate exclusions so files are tracked in notes branch
!**/README.md
!CLAUDE.md
!scripts/

# Ignore system files
.DS_Store
```

### Step 5: Create Scripts Symlink

```bash
ln -s notes/scripts scripts
```

## The Dual Exclusion Strategy

This is the key insight that makes the pattern work cleanly.

### The Problem

Without proper exclusions:
- Main branch shows symlinks as "new files" to commit
- Notes branch shows files as "deleted"
- Both branches have confusing git status

### The Solution

**Layer 1: Main Branch Exclusion**

The exclusion file (either `.git/info/exclude` or `.gitignore`) tells git to ignore:
- The `notes/` directory entirely
- All symlinked documentation files

This keeps `git status` in the main branch clean.

**Layer 2: Notes Branch Negation**

The `notes/.gitignore` uses negation patterns (`!pattern`) to override exclusions:
```
!**/README.md
```

Git processes `.gitignore` files in order. When you're in the notes worktree, the `notes/.gitignore` takes precedence and "un-ignores" the documentation files.

### Why This Works

When in main branch:
1. Git checks `.gitignore` or `.git/info/exclude`
2. Finds patterns matching `client/README.md` (symlink)
3. Ignores the symlink - clean status

When in notes worktree:
1. Git checks `notes/.gitignore`
2. Finds negation `!**/README.md`
3. Tracks the actual file

## Exclusion Method Comparison

| Aspect | .git/info/exclude | .gitignore |
|--------|-------------------|------------|
| Tracked | No (local only) | Yes (shared) |
| Team setup | Each person runs init | Automatic |
| Root README | Included in exclusions | Negated with `!/README.md` |
| Best for | Personal workflow | Team projects |

### When to Use .git/info/exclude

- Testing the pattern before team adoption
- Personal documentation others don't need
- Gradual rollout (some devs use it, others don't)
- Fork-specific documentation

### When to Use .gitignore

- Team-wide documentation
- Consistent setup across all clones
- CI/CD needs to know about exclusions
- Onboarding is simplified

## Configuration File (.notesrc)

The scripts store configuration in `notes/.notesrc`:

```json
{
  "branch": "notes",
  "worktree": "./notes",
  "exclusion_method": "gitignore",
  "exclude_root_readme": true
}
```

This allows `sync-notes.sh` to know which exclusion file to update.

## Symlink Details

### Relative vs Absolute Paths

The scripts create relative symlinks:
```bash
# From client/README.md to notes/client/README.md
ln -s ../notes/client/README.md client/README.md
```

Relative symlinks work regardless of where the repository is cloned.

### Calculating Relative Paths

The scripts use Python to calculate paths:
```bash
rel_path=$(python3 -c "import os.path; print(os.path.relpath('$target', '$source_dir'))")
```

### Verifying Symlinks

Check if a file is a symlink:
```bash
ls -la client/README.md
# Output: client/README.md -> ../notes/client/README.md
```

Check if symlink target exists:
```bash
readlink -f client/README.md
# Output: /full/path/to/notes/client/README.md
```

## Troubleshooting

### "Branch already exists"

The init script only creates new branches. If the branch exists:

1. **Use existing branch**: Set up worktree manually
   ```bash
   git worktree add ./notes notes
   ./scripts/sync-notes.sh
   ```

2. **Choose different name**: Run init with different branch name

3. **Delete and recreate** (destructive):
   ```bash
   git branch -D notes  # Delete local
   git push origin --delete notes  # Delete remote
   ```

### Symlinks Showing in Git Status

The exclusion file is missing entries. Run:
```bash
./scripts/sync-notes.sh
```

Or manually add the path to your exclusion file.

### "notes worktree not found"

The worktree isn't set up. Add it:
```bash
git worktree add ./notes notes
```

If the branch doesn't exist on remote:
```bash
git fetch origin notes:notes
git worktree add ./notes notes
```

### Merge Conflicts in Exclusion Files

If using `.gitignore` and multiple people add different docs, you may get merge conflicts. The sync script uses markers to manage its section:

```
# >>> sync-notes managed entries >>>
...auto-generated entries...
# <<< sync-notes managed entries <<<
```

Resolve by keeping the markers and entries from both branches, then run `sync-notes.sh` to deduplicate.

### Symlink Points to Wrong Location

Remove and recreate:
```bash
rm client/README.md
./scripts/sync-notes.sh
```

### Permission Denied on Scripts

```bash
chmod +x notes/scripts/*.sh
# or
chmod +x scripts/*.sh
```

### Notes Directory Shows Modified Files After Clone

After cloning, the notes worktree may show files as modified if line endings differ. Configure git:
```bash
cd notes
git config core.autocrlf input  # On Mac/Linux
git checkout -- .
```

## Team Workflows

### Initial Setup (Team Lead)

1. Run `init-notes-worktree.sh` with `.gitignore` method
2. Move existing documentation
3. Commit and push both branches:
   ```bash
   # Main branch
   git add .gitignore
   git commit -m "Add notes worktree exclusions"
   git push

   # Notes branch
   cd notes
   git add -A
   git commit -m "Initial documentation"
   git push -u origin notes
   ```

### Team Member Setup

After cloning:
```bash
git worktree add ./notes notes
./scripts/sync-notes.sh
```

The `.gitignore` is already configured, symlinks are created by sync.

### CI/CD Considerations

If CI needs documentation:
```yaml
# GitHub Actions example
- name: Checkout
  uses: actions/checkout@v4

- name: Setup notes worktree
  run: |
    git fetch origin notes
    git worktree add ./notes notes
```

If CI doesn't need documentation, the notes worktree can be skipped - the main branch works independently.

## Advanced Usage

### Multiple Documentation Branches

You can have multiple worktrees for different purposes:
```bash
git worktree add ./docs docs        # Public documentation
git worktree add ./internal internal-docs  # Internal docs
```

### Partial Sync

To sync only specific directories:
```bash
# Edit sync-notes.sh or create a wrapper
./scripts/sync-notes.sh --path client/
```

### Integration with Documentation Tools

The combined markdown output works with:
- **Pandoc**: Convert to PDF, DOCX, HTML
- **MkDocs**: Use combined output as content
- **Docusaurus**: Process markdown into static site
- **Confluence**: Import combined document

Example with Pandoc:
```bash
./scripts/combine-notes.sh | pandoc \
  --toc \
  --toc-depth=3 \
  -V geometry:margin=1in \
  -o documentation.pdf
```
