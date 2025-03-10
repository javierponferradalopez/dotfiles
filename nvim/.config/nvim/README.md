# My LazyVim configuration

Configuration user for [LazyVim](https://www.lazyvim.org/)

## 🛠️ Install

#### Requeriments
* Neovim >= 0.9.0 ([INSTALL.md](https://github.com/neovim/neovim/blob/master/INSTALL.md))
* Use Nerd Font (I recommend  [JetBrains Mono](https://www.programmingfonts.org/#jetbrainsmono))
* For `telescope.nvim`
  * live grep: `ripgrep`
  * find files: `fd-find`
* For `LuaShip`
  * `make`
* For `nvim-treesitter`
  * `gcc` (C compiler for nvim-treesitter).
  * `g++`
  * `nodejs`


Linux
```shell
sudo apt-get install -y gcc ripgrep fd-find g++ make
```
Macos
```shell
sudo brew install gcc ripgrep fd make
```
>[!NOTE]
>For install `nodejs` I recommend use [nvm](https://github.com/nvm-sh/nvm)

#### Clone the repository

You can also just clone this repository directly if you do not want to track your user configuration in GitHub.
Clone repository in temporal folder

```shell
git clone https://github.com/jponferrada26/dotnvim /tmp/dotnvim
```

#### Backup old nvim configuration

```shell
mv ~/.config/nvim ~/.config/nvim.bak

```

#### Remove temporal files (Recommended)

```shell
mv ~/.local/share/nvim
mv ~/.local/state/nvim
mv ~/.cache/nvim
```

#### Extract LazyNvim configuration and move to your nvim

```shell
cp -r /tmp/dotnvim/lazyvim ~/.config/nvim
```

#### Start Neovim

```shell
nvim
```
