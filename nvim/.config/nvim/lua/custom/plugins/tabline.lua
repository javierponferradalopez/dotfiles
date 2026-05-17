require('mini.tabline').setup()

vim.keymap.set('n', '<S-h>', '<cmd>bprevious<cr>', { desc = 'Prev buffer' })
vim.keymap.set('n', '<S-l>', '<cmd>bnext<cr>', { desc = 'Next buffer' })
vim.keymap.set('n', '<leader>bd', function()
  local buf = vim.api.nvim_get_current_buf()
  local wins = vim.fn.win_findbuf(buf)
  if #wins > 0 then
    vim.cmd 'bprevious'
  end
  vim.api.nvim_buf_delete(buf, { force = false })
end, { desc = 'Delete buffer' })
