RED='\033[0;31m'
NC='\033[0m' # No Color

brew_install() {
  echo "\nInstalling $1"
  if brew list $1 &>/dev/null; then
    echo "${1} is already installed"
  else
    brew install $1 && echo "$1 installed"
  fi
}

echo "\nGeneral dependencies -----"
brew_install "nvm"
brew_install "git"
brew_install "stow"
brew_install "zsh"
brew_install "zsh-vi-mode"
brew_install "spaceship"
brew_install "jq"
brew_install "herdr"
brew_install "go" # Herdr builds some plugins from source with Go
echo "\n-------------------------"

echo "\nNvim's dependencies -----"
brew_install "neovim"
brew_install "gcc"
brew_install "ripgrep"
brew_install "fd"
brew_install "make"
brew_install "fzf"
brew_install "tree-sitter-cli"
echo "\n-------------------------"

echo "\nHerdr plugins -----------"
"$(dirname "$0")/herdr-plugins.sh"
echo "\n-------------------------"

echo "\nClaude Code -------------"
brew_install "claude-code@latest"
brew_install "gitbutler" # Gives the `but` CLI
herdr integration install claude
# Write the skills again on each run, so they match the installed CLI.
but skill install --path "$HOME/.claude/skills/gitbutler"
mkdir -p "$HOME/.claude/skills/herdr"
herdr --skill > "$HOME/.claude/skills/herdr/SKILL.md"
echo "\n-------------------------"

echo "\n${RED}Remember to install a Nerd Font (https://www.nerdfonts.com/font-downloads)${NC}"
