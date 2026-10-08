# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# user-local binaries (aws cli, etc.) — por delante de /usr/local/bin
export PATH="$HOME/.local/bin:$PATH"

# rust toolchain (rustup didn't write this itself: ~/.zshrc is a symlink into the dotfiles)
export PATH="$HOME/.cargo/bin:$PATH"

# editor
export EDITOR=nvim

# completion system (enables Tab autocompletion)
autoload -Uz compinit && compinit

# navigable selection menu (arrow keys) and case-insensitive matching
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# history: share it between all the shells (herdr panes) at each command
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY          # write each command at once and read the commands of other shells
setopt EXTENDED_HISTORY       # store the time of each command
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS

# prompt
# Keep only the sections we use. Each async section starts one job and some
# processes for each new shell. With the 63 default sections, herdr starts
# about 20 shells at the same time and the user gets to the process limit.
SPACESHIP_PROMPT_ORDER=(
  user dir host git node aws exec_time async line_sep jobs exit_code sudo char
)
source "$(brew --prefix)/opt/spaceship/spaceship.zsh"

# vi mode (must be sourced last; it re-initializes zle)
source "$(brew --prefix)/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh"
