## What this is

A personal Neovim configuration (Neovim >= 0.11), originally forked from kickstart.nvim. It lives inside a larger `dotfiles` repo and is symlinked into `~/.config/nvim` via GNU Stow (`stow -t $HOME -v nvim` from the dotfiles root).

## Commands

- **Format Lua**: `stylua .` (config in `.stylua.toml`: 2-space indent, single quotes preferred, no call parens, 160 column width). This is the only build/lint tooling — there is no test suite for the config itself.
- **Reload after edits**: changes take effect on next `nvim` launch (or `:source %` / `:Lazy`-equivalents are not used here).
- **Update plugins**: `:lua vim.pack.update()` (or `vim.pack.update(nil, { offline = true })` to just re-read the lockfile).

## Architecture

### Plugin management: native `vim.pack`, NOT lazy.nvim

This config uses Neovim's built-in `vim.pack` (0.11+). There is no lazy.nvim, packer, or any third-party manager. Consequences:

- Plugins are installed by calling `vim.pack.add { 'https://github.com/owner/repo' }` directly in code, then configured immediately after (synchronous, eager — no lazy-loading spec tables).
- `nvim-pack-lock.json` pins exact plugin revisions and **is committed**. Treat it like a lockfile.
- Plugins needing a compile/post-install step are handled by a single `PackChanged` autocmd in **SECTION 2** of `init.lua` (the `run_build` helper). When adding a plugin that needs a build (e.g. native make, `TSUpdate`), add a new branch there keyed on `ev.data.spec.name` — do not invent a separate mechanism.

### `init.lua` is the core, organized in 9 numbered sections

The ~1000-line `init.lua` holds the whole base config, split into commented sections each wrapped in a `do ... end` block for local scoping:

1. Foundation (options, leaders, base keymaps, autocmds)
2. Plugin manager (`vim.pack` build hooks + the `gh(repo)` URL helper)
3. UI / Core UX (colorscheme, which-key, mini.nvim modules, statusline)
4. Search & Navigation (Telescope + extensions)
5. LSP (fidget, mason, LspAttach keymaps)
6. Formatting (conform.nvim → biome / prettierd / stylua)
7. Autocomplete & Snippets (blink.cmp + LuaSnip)
8. Treesitter (auto-install on FileType)
9. User plugins loader

The `gh(repo)` helper (defined at the end of SECTION 2) builds GitHub URLs to cut repetition — use it for new `vim.pack.add` calls in `init.lua`.

### User plugins: `lua/custom/plugins/`

Every `.lua` file here (except `init.lua`) is **auto-required** by the loop in `lua/custom/plugins/init.lua`. To add a plugin, just drop a new self-contained file in this directory — no registration needed. Conventions for these files:

- Each file calls its **own** `vim.pack.add { ... }` for its dependencies (full GitHub URLs, the `gh` helper is not in scope here), then configures and sets its own keymaps.
- Dependencies already provided by `init.lua` (plenary, nvim-treesitter, web-devicons) are reused, not re-added — note this in a comment as existing files do.
- which-key **group** labels (e.g. `[R]un`, `[G]it`) are registered centrally in `init.lua`'s which-key spec, while the actual leader keymaps live in the relevant plugin file.

`lua/custom/git_browser.lua` is a shared local module (not a plugin) required by other custom files — keep cross-file helpers like this as plain modules under `lua/custom/`.

## Conventions

- Keymap descriptions use the `[X]` bracket convention to mark the mnemonic letter (e.g. `'[G]it [B]lame'`), which feeds which-key.
- Comments and docstrings are written in English.
- Match the surrounding kickstart-derived style: heavy explanatory comments, `vim.o` for scalar options and `vim.opt` only when a table interface is needed.
