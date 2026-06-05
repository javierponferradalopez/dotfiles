vim.pack.add { 'https://github.com/lukas-reineke/indent-blankline.nvim' }

-- Vertical guides on every indentation level, plus a highlighted guide for
-- the scope under the cursor (uses treesitter, already configured).
require('ibl').setup {
  indent = { char = '│' },
  scope = { enabled = true },
}
