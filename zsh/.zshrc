# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# user-local binaries (aws cli, etc.) — por delante de /usr/local/bin
export PATH="$HOME/.local/bin:$PATH"

# editor
export EDITOR=nvim

# completion system (enables Tab autocompletion)
autoload -Uz compinit && compinit

# navigable selection menu (arrow keys) and case-insensitive matching
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# prompt
source "$(brew --prefix)/opt/spaceship/spaceship.zsh"

# vi mode (must be sourced last; it re-initializes zle)
source "$(brew --prefix)/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh"
