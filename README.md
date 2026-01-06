# gwa - Git Worktree for AI

A fast, cross-platform Git worktree management CLI written in Zig, designed for AI-assisted development workflows.

## Features

- **Worktree Management**: Create, remove, and list git worktrees with simplified commands
- **Status Overview**: Pretty table showing branch, dirty state, and last commit across all worktrees
- **Branch Synchronization**: Sync worktrees with base branch via rebase or merge
- **Editor/AI Integration**: Open worktrees in editors (VS Code, Cursor, Zed) or launch AI tools (Claude, Aider)
- **Smart Automation**: File copying, hooks, and cross-worktree command execution
- **Metadata**: Notes, locking, and cleanup management

## Installation

### Homebrew (macOS/Linux)

```bash
brew tap ethan-k/gwa
brew install gwa
```

### Build from Source

Requires Zig 0.15+:

```bash
git clone https://github.com/ethan-k/gwa.git
cd gwa
make install
```

Or manually:

```bash
zig build -Doptimize=ReleaseFast
cp ./zig-out/bin/gwa ~/.local/bin/
```

## Usage

```
gwa <command> [arguments]
```

### Core Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `gwa list` | `ls` | List all worktrees |
| `gwa status` | `st` | Show worktree status with dirty state and last commit |
| `gwa new <branch>` | `add`, `a` | Create a new worktree |
| `gwa rm <branch>` | `del`, `d` | Remove a worktree |

### Branch Operations

| Command | Alias | Description |
|---------|-------|-------------|
| `gwa sync <name>` | `sy` | Sync worktree with base branch (rebase/merge) |
| `gwa apply <name>` | `merge`, `ap` | Apply worktree changes to target branch |

### Editor/AI Integration

| Command | Description |
|---------|-------------|
| `gwa editor <name>` | Open worktree in editor (code, cursor, zed) |
| `gwa ai <name>` | Launch AI tool in worktree (claude, aider) |
| `gwa run <name> <cmd>` | Run command in worktree directory |

### Metadata & Utilities

| Command | Alias | Description |
|---------|-------|-------------|
| `gwa note <name> <text>` | `n` | Add note to worktree |
| `gwa info <name>` | `i` | Show worktree metadata |
| `gwa lock <name>` | | Lock worktree from deletion |
| `gwa unlock <name>` | | Unlock worktree |
| `gwa gc` | | Show cleanup candidates |
| `gwa cd <name>` | | Output worktree path |
| `gwa exec <cmd>` | | Run command across all worktrees |
| `gwa config` | | Edit or show configuration |

## Examples

### List all worktrees

```bash
$ gwa list
PATH                                     BRANCH
---------------------------------------- --------------------
/home/user/project                       main
/home/user/project-feature-x             feature-x
```

### Check status across worktrees

```bash
$ gwa status
PATH                           BRANCH               DIRTY    LAST COMMIT
------------------------------ -------------------- -------- ----------------------------------------
/home/user/project             main                 no       Merge branch 'feature-y' into main
/home/user/project-feature-x   feature-x            yes      WIP: Add new feature
```

### Create a new worktree

```bash
$ gwa new feature-z
Created worktree for branch: feature-z
```

### Launch AI tool in worktree

```bash
$ gwa ai feature-z claude
Launching claude in /home/user/project-feature-z...
```

### Run command across all worktrees

```bash
$ gwa exec "git status"
=== main (/home/user/project) ===
On branch main
nothing to commit, working tree clean

=== feature-z (/home/user/project-feature-z) ===
On branch feature-z
Changes not staged for commit:
...
```

## Configuration

### Config Command

```bash
gwa config              # Edit project config in default editor (vim)
gwa config --global     # Edit global config
gwa config -e code      # Edit with specific editor
gwa config show         # Show current effective configuration
gwa config path         # Show config file locations
```

### Config Files

- `~/.config/gwa/config.toml` - Global settings
- `<repo>/.gwa/config.toml` - Project settings (overrides global)

### Available Options

```toml
# Default base branch for new worktrees
default_base = "main"

# Editor for `gwa editor` command (default: vim)
editor = "cursor"

# AI tool for `gwa ai` command (default: claude)
ai_tool = "claude"

# Files to copy to new worktrees
copy_files = [".env", ".envrc"]

# Directories to copy to new worktrees
copy_dirs = ["node_modules"]

# Hooks
post_create_hook = "npm install"
pre_remove_hook = "git stash"

# Custom worktrees directory (default: sibling to repo)
worktrees_dir = "/path/to/worktrees"
```

## Development

```bash
make build     # Debug build
make release   # Optimized build
make test      # Run tests
make install   # Install to ~/.local/bin
make clean     # Clean build artifacts
```

## Why Zig?

- **Fast**: Native performance with no runtime overhead
- **Safe**: Memory safety without garbage collection
- **Simple**: Single binary, no dependencies
- **Cross-platform**: Compiles to any target from any host

## License

MIT
