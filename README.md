# dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).
Each top-level directory is a Stow *package* that mirrors the layout it should
have under `$HOME`, so symlinking it places every file in its expected location.

## Packages

| Package     | Application        | Symlinks into                        |
| ----------- | ------------------ | ------------------------------------ |
| `zsh`       | Zsh (+ vi mode)    | `~/.zshrc`                           |
| `alacritty` | Alacritty terminal | `~/.config/alacritty/`               |
| `nvim`      | Neovim             | `~/.config/nvim/`                    |
| `git`       | Git                | `~/.gitconfig`                       |
| `claude`    | Claude Code        | `~/.claude/` (settings, statusline…) |
| `herdr`     | Herdr multiplexer  | `~/.config/herdr/config.toml`        |

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

### 2. Symlink the packages

Run from the repository root, choosing the packages you want:

```bash
stow -t $HOME -v zsh alacritty nvim git claude
```

`herdr` must be stowed with `--no-folding` so that `~/.config/herdr` stays a
real directory and only `config.toml` is symlinked. Without it, Stow folds the
whole directory into a single symlink and Herdr's runtime files (logs, session,
sockets…) end up written back inside this repository:

```bash
stow -t $HOME -v --no-folding herdr
```

## Uninstall

Remove the symlinks for any package with the `-D` flag:

```bash
stow -t $HOME -v -D zsh alacritty nvim git claude herdr
```
