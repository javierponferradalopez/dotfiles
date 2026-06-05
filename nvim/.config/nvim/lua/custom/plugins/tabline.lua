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

-- Delete every *other* listed buffer, keeping the focused one.
vim.keymap.set('n', '<leader>bo', function()
  local current = vim.api.nvim_get_current_buf()
  local kept = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= current and vim.bo[buf].buflisted then
      -- force = false respects unsaved changes; skip (and count) any that refuse.
      if not pcall(vim.api.nvim_buf_delete, buf, { force = false }) then kept = kept + 1 end
    end
  end
  if kept > 0 then
    vim.notify(kept .. ' buffer(s) kept (unsaved changes)', vim.log.levels.WARN)
  end
end, { desc = 'Delete [O]ther buffers' })

-- Delete all listed buffers and drop back to the dashboard.
vim.keymap.set('n', '<leader>bD', function()
  local kept = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then
      if not pcall(vim.api.nvim_buf_delete, buf, { force = false }) then kept = kept + 1 end
    end
  end
  if kept > 0 then
    vim.notify(kept .. ' buffer(s) kept (unsaved changes)', vim.log.levels.WARN)
  end
  require('mini.starter').open()
end, { desc = '[D]elete all buffers → dashboard' })
