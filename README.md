# dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).
Each top-level directory is a Stow *package* that mirrors the layout it should
have under `$HOME`, so symlinking it places every file in its expected location.

## Packages

| Package     | Application        | Symlinks into                        |
| ----------- | ------------------ | ------------------------------------ |
| `alacritty` | Alacritty terminal | `~/.config/alacritty/`               |
| `nvim`      | Neovim             | `~/.config/nvim/`                    |
| `ideavim`   | IdeaVim (WebStorm) | `~/.ideavimrc`                       |
| `git`       | Git                | `~/.gitconfig`                       |
| `claude`    | Claude Code        | `~/.claude/` (settings, statusline…) |

## Installation

> [!WARNING]
> Back up any existing dotfiles before symlinking. Stow refuses to overwrite
> real files and will report a conflict instead.

### 1. Install dependencies

On macOS, run the bootstrap script. It installs the base tools (GNU Stow,
`git`, `jq`, …) and Neovim's dependencies via Homebrew, skipping anything
already present:

```bash
./scripts/installation.sh
```

> [`jq`](https://stedolan.github.io/jq/) is required by the Claude Code
> statusline, and [GNU Stow](https://www.gnu.org/software/stow/) by every step
> below.

### 2. Symlink the packages

Run from the repository root, choosing the packages you want. For the Neovim
setup:

```bash
stow -t $HOME -v alacritty nvim git claude
```

For the WebStorm / IdeaVim setup:

```bash
stow -t $HOME -v alacritty ideavim git claude
```

### 3. Claude Code (first time only)

`~/.claude` usually already exists with its own files (sessions, history, …),
so the first time use `--adopt` to take ownership of the existing config files.
They are identical to the ones tracked here, so nothing is lost:

```bash
stow -t $HOME -v --adopt claude
```

This only links the tracked files (`settings.json`, `statusline-command.sh`
and `CLAUDE.md`); everything else under `~/.claude` is left untouched.

## Uninstall

Remove the symlinks for any package with the `-D` flag:

```bash
stow -t $HOME -v -D alacritty nvim git claude
```
