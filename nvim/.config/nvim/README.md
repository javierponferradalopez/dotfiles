# My Neovim configuration

Personal Neovim config built on native `vim.pack` (no lazy.nvim).

## Requirements

- Neovim >= 0.11
- [Nerd Font](https://www.nerdfonts.com/) (recommended: [JetBrains Mono](https://www.programmingfonts.org/#jetbrainsmono))
- `ripgrep` — for Telescope live grep
- `fd` — for Telescope file finder
- `gcc` / `g++` — for nvim-treesitter
- `make` — for LuaSnip / telescope-fzf-native
- `nodejs` — for some LSP servers (recommended via [nvm](https://github.com/nvm-sh/nvm))

macOS:
```shell
brew install gcc ripgrep fd make
```

Linux:
```shell
sudo apt-get install -y gcc ripgrep fd-find g++ make
```

## Install

```shell
# Backup existing config
mv ~/.config/nvim ~/.config/nvim.bak
mv ~/.local/share/nvim ~/.local/share/nvim.bak
mv ~/.local/state/nvim ~/.local/state/nvim.bak
mv ~/.cache/nvim ~/.cache/nvim.bak

# Clone
git clone https://github.com/jponferrada26/dotnvim ~/.config/nvim

# Start (plugins install automatically on first run)
nvim
```

## Structure

```
init.lua                     — single-file config, organized in numbered sections
lua/custom/plugins/          — user plugins (auto-loaded, one file per plugin)
  dashboard.lua              — mini.starter dashboard
  neo-tree.lua               — file explorer (<leader>e)
  tabline.lua                — mini.tabline with buffer navigation
  rip-substitute.lua         — search/replace with ripgrep (<leader>fs)
  subproject.lua             — per-directory project focus (<leader>sp)
```

## Key sections in init.lua

| # | Section | Contents |
|---|---------|----------|
| 1 | Foundation | Options, leaders, keymaps, autocmds |
| 2 | Plugin manager | `vim.pack` setup, build hooks |
| 3 | UI / Core UX | Colorscheme, which-key, mini.ai, mini.surround, statusline |
| 4 | Search & Navigation | Telescope + extensions |
| 5 | LSP | fidget, mason, mason-lspconfig, LspAttach keymaps |
| 6 | Formatting | conform.nvim (biome / prettierd / stylua) |
| 7 | Autocomplete & Snippets | blink.cmp + LuaSnip |
| 8 | Treesitter | nvim-treesitter (auto-install on FileType) |
| 9 | User plugins | loads `lua/custom/plugins/` |

---

Originally forked from [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim).
