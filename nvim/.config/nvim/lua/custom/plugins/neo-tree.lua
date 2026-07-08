vim.pack.add {
  'https://github.com/nvim-neo-tree/neo-tree.nvim',
  'https://github.com/MunifTanjim/nui.nvim',
}

vim.keymap.set('n', '<leader>e', function()
  -- Only `reveal` when the current buffer is a real file on disk. On scratch
  -- buffers like the mini.starter dashboard (name `ministarter://1`) reveal
  -- would prompt to change cwd to a non-existent path, so just focus instead.
  local path = vim.api.nvim_buf_get_name(0)
  if path ~= '' and vim.fn.filereadable(path) == 1 then
    vim.cmd 'Neotree reveal'
  else
    vim.cmd 'Neotree focus'
  end
end, { desc = '[E]xplorer reveal current file (focus)' })
vim.keymap.set('n', '<leader>E', '<Cmd>Neotree show<CR>', { desc = '[E]xplorer open (no focus)' })

require('neo-tree').setup {
  close_if_last_window = true,
  filesystem = {
    follow_current_file = { enabled = false },
    hijack_netrw_behavior = 'open_current',
    -- Only treat dotfiles (names starting with `.`) as hidden. Don't hide
    -- gitignored or untracked files, which neo-tree masks by default.
    filtered_items = {
      hide_dotfiles = true,
      hide_gitignored = false,
      hide_hidden = false,
    },
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
