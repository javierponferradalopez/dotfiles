# dotfiles

### Requirements

- [GNU Stow](https://www.gnu.org/software/stow/)

### Installation

> :warning: **Warning**: Remember to backup your dotfiles before the symlink is done

We must use the param "--recursive" because it includes the submodules. 

```bash
git clone --recursive ...
```

We need to source all of the configurations by running the following command:

```bash
stow -t $HOME -v alacritty nvim tmux
```
