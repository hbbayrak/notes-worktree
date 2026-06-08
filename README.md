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

Add this repository as a plugin marketplace, then install the plugin — both from inside Claude Code:

```text
/plugin marketplace add hbbayrak/notes-worktree
/plugin install notes-worktree@notes-worktree-marketplace
```

`/plugin marketplace add` also accepts a full git URL or a local path, e.g.
`/plugin marketplace add https://github.com/hbbayrak/notes-worktree`.

## Updating

Plugins are **pull-based** — you receive a new version when you refresh the marketplace, not automatically. (Auto-update is off by default for third-party marketplaces.) When a new version is released:

```text
/plugin marketplace update notes-worktree-marketplace   # pull the latest version
/reload-plugins                                          # activate it in this session
```

To enable automatic updates for this marketplace, toggle it via `/plugin` → **Marketplaces**.

> Each version is cached separately under `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. If you set up a notes worktree before updating, the `notes/scripts` symlink is **refreshed automatically** the next time you run `sync-notes.sh`, `status-notes.sh`, or `cleanup-notes.sh` (or re-run `init-notes-worktree.sh`) — no manual step needed.

## Usage

### Ask Claude

Simply ask Claude to set up notes worktree:

> "Set up a notes worktree for this project"
> "Separate my documentation into a different branch"
> "Create a docs branch with symlinks"

### Manual Setup

Run the init script directly from a clone of this repo (the same scripts are bundled inside the installed plugin).

**Preview first** — the sweep moves *every* markdown file (except the root `README.md`) into the notes branch, so see what would move (and keep code-adjacent docs in main) before committing:

```bash
# No changes — lists what would move, grouped by directory, flags code-adjacent trees:
./plugins/notes-worktree/skills/notes-worktree/scripts/init-notes-worktree.sh --dry-run
./plugins/notes-worktree/skills/notes-worktree/scripts/init-notes-worktree.sh --dry-run --exclude "src/,packages/"
```

Then run the real setup:

```bash
./plugins/notes-worktree/skills/notes-worktree/scripts/init-notes-worktree.sh \
  --branch notes \
  --dir ./notes \
  --exclusion gitignore \
  [--move-files] [--vscode] [--exclude "SKILL.md,src/,docs/superpowers/"]
```

For a new branch, `--branch`, `--dir`, and `--exclusion` are required:
- `--exclusion gitignore` — team-shared exclusions via `.gitignore`
- `--exclusion exclude` — local-only exclusions via `.git/info/exclude`
- `--move-files` — move existing `.md` files into the notes branch and symlink them
- `--vscode` — hide the notes directory in VSCode
- `--dry-run` — preview the sweep and exit without making changes
- `--exclude PATTERNS` — comma-separated patterns to **keep in main**. These can be
  filenames, globs, **or directory subtrees**, not just filenames:
  - `SKILL.md` — a file by name (matched anywhere)
  - `*.generated.md` — a basename glob
  - `src/` or `src/**` — keep the entire `src/` subtree in main
  - `docs/superpowers/` — keep a nested subtree

  A pattern with **no slash** matches by basename (legacy behavior); include a
  slash (e.g. `src/`) to exclude a directory. See
  [the exclude pattern syntax reference](plugins/notes-worktree/skills/notes-worktree/references/setup-guide.md#exclude-pattern-syntax)
  for the full table and the `*`-crosses-`/` caveat.

If the branch already exists (locally or on a remote), its configuration is read from `.notesrc` and you can run with just `--branch <name>`. In that case `init` also **materializes the documentation symlinks** (via a symlinks-only reverse sync), so a fresh clone is usable in one step without a separate sync.

### After Setup

```bash
# Sync new documentation files
./notes/scripts/sync-notes.sh

# Generate combined documentation
./notes/scripts/combine-notes.sh > all-docs.md
./notes/scripts/combine-notes.sh | pandoc -o docs.pdf

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
└── notes/             # Worktree (notes branch)
    ├── scripts        # Symlink → plugin scripts
    ├── client/
    │   └── README.md  # Actual file
    └── server/
        └── README.md  # Actual file
```

- **Main branch**: Contains code + symlinks to docs
- **Notes branch**: Contains actual documentation files
- **Symlinks**: Make docs accessible in expected locations

## Scripts

| Script | Purpose |
|--------|---------|
| `init-notes-worktree.sh` | Interactive setup for new projects |
| `sync-notes.sh` | Bidirectional sync with --dry-run, --cleanup, --watch, --reverse-only |
| `status-notes.sh` | Health check and sync status report |
| `cleanup-notes.sh` | Fix dangling symlinks and stale exclusions |
| `teardown-notes.sh` | Clean uninstall of the setup |
| `notes-commit.sh` | Quick commit helper for notes branch |
| `notes-push.sh` | Push notes branch to remote |
| `notes-pull.sh` | Pull and sync symlinks |
| `combine-notes.sh` | Generate combined markdown document |
| `manage-excludes.sh` | Add, remove, or list exclusion patterns |

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
