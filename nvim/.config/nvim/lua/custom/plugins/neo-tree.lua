vim.pack.add {
  'https://github.com/nvim-neo-tree/neo-tree.nvim',
  'https://github.com/MunifTanjim/nui.nvim',
}

vim.keymap.set('n', '<leader>e', '<Cmd>Neotree toggle<CR>', { desc = '[E]xplorer toggle' })
vim.keymap.set('n', '<leader>E', '<Cmd>Neotree reveal<CR>', { desc = '[E]xplorer reveal current file' })

require('neo-tree').setup {
  close_if_last_window = true,
  filesystem = {
    follow_current_file = { enabled = false },
    hijack_netrw_behavior = 'open_current',
    window = {
      mappings = {
        ['<leader>e'] = 'close_window',
      },
    },
  },
  window = {
    width = 35,
  },
}
