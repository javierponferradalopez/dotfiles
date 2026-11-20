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
| `herdr`     | Herdr multiplexer  | `~/.config/herdr/config.toml`        |
| `herdr-app` | Herdr desktop app  | `~/.config/herdr-app/` (single files) |
| `pi`        | Pi coding agent    | `~/.pi/agent/` (single files)        |


## Installation

> [!WARNING]
> Back up any existing dotfiles before symlinking. Stow refuses to overwrite
> real files and will report a conflict instead.

### 1. Install dependencies

On macOS, run the bootstrap script. It installs the base tools (GNU Stow,
`git`, `jq`, …), Neovim's dependencies, the Herdr plugins and Pi, with its
Herdr integration, skipping anything already present:

```bash
./scripts/installation.sh
```

### 2. Symlink the packages

Run from the repository root, choosing the packages you want:

```bash
stow -t $HOME -v zsh alacritty nvim git
```

`herdr` must be stowed with `--no-folding` so that `~/.config/herdr` stays a
real directory and only `config.toml` is symlinked. Without it, Stow folds the
whole directory into a single symlink and Herdr's runtime files (logs, session,
sockets…) end up written back inside this repository:

```bash
stow -t $HOME -v --no-folding herdr
```

`herdr-app` must also be stowed with `--no-folding`. `~/.config/herdr-app`
holds the app's state (`view.json`, `shared.json`, `data/`…) and the files it
rewrites on each start (`AGENTS.md`, `*.d.ts`, the shipped layouts and mods):

```bash
stow -t $HOME -v --no-folding herdr-app
```

If the app already started on that machine, remove its `settings.json` and
`keys.json` first, or Stow reports a conflict. While the symlinks are not
there, the running app writes new default files in their place.

Then, with the app open, install the mods that this config uses (see
[Mods](#mods)):

```bash
./scripts/herdr-app-mods.sh
```

`pi` must also be stowed with `--no-folding`. `~/.pi/agent` holds Pi's
credentials (`auth.json`), sessions and install files, which must stay out of
this repository:

```bash
stow -t $HOME -v --no-folding pi
```

### Herdr plugins

`scripts/herdr-plugins.txt` holds the Herdr plugins, one GitHub
`<owner>/<repo>` on each line. To add a plugin, add its line and run:

```bash
./scripts/herdr-plugins.sh
```

The script installs only the plugins that are not installed yet. Herdr starts
a new plugin when its server starts, so restart the server or invoke the
plugin's restart action after the install.

### Herdr app

Install the app from [herdr.dev](https://herdr.dev). The package holds only
the files that you write:

| File                  | What it holds                                         |
| --------------------- | ----------------------------------------------------- |
| `settings.json`       | Terminal font, sounds, worktree directory             |
| `keys.json`           | Shortcuts: the defaults, plus `cmd-shift-g` (gitview panel) and `cmd-g` (gitview tab) |
| `themes/<name>.json`  | Custom themes (none yet)                              |
| `layouts/custom.json` | The layout in use: a copy of `main`, with gitview in the Changes panel |

Do not add the layouts and mods that Herdr ships (`main`, `terminals`, `win98`,
`spaces`, `tabs`…): the app replaces them on each start. To keep a new layout
or theme, move it into this package and run the `stow` command again.

#### Mods

Mod code is not kept here. `scripts/herdr-app-mods.txt` lists the mods, one on
each line: the GitHub repo, the release tag to install, and the local patches
for that tag:

```
ChmaraX/herdr-gitview v0.6.0 herdr-gitview-v0.6.0-diff-in-tab.patch
```

`scripts/herdr-app-mods.sh` installs each mod with its own installer at that
tag, then applies its patches from `scripts/patches/`. A patch is made against
the tag of its line, and its file name says which tag. The script stops when a
patch does not apply, and changes no mod file for that patch.

To upgrade a mod: change its tag, make each patch again against the new tag
(and rename it), and run the script. To make a patch: install the tag without
the patch, keep a copy of the files, make the change, and run
`diff -ru a b` from a folder that holds the copy as `a/<mod>/` and the changed
files as `b/<mod>/`.

The installers add their keys only where they are free, and edit the layout
only when it does not have their mod yet. With the `keys.json` and
`layouts/custom.json` of this package, they write neither, so the symlinks stay.

[gitview](https://github.com/ChmaraX/herdr-gitview) shows the repo changes in
the Changes panel (`cmd-shift-g`) and in a tab of its own (`cmd-g`). Its patch
makes a click on a file in the Changes panel open the diff in the gitview tab,
not in a split that makes the terminals narrower.

The app writes `settings.json` through the symlink when you change a setting,
so the changes come into this repository. Commit them.

The app does not update an edited `keys.json` on upgrade. To get the new default
shortcuts, add them by hand.

## Uninstall

Remove the symlinks for any package with the `-D` flag:

```bash
stow -t $HOME -v -D zsh alacritty nvim git herdr herdr-app pi
```
