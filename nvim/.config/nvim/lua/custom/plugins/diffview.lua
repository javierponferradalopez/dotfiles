vim.pack.add { 'https://github.com/sindrets/diffview.nvim' }

require('diffview').setup {}

local function default_branch()
  local function git(args)
    local out = vim.fn.systemlist(vim.list_extend({ 'git' }, args))
    if vim.v.shell_error ~= 0 then return nil end
    return out[1]
  end

  local head_ref = git { 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD' }
  if head_ref then return head_ref end
  for _, b in ipairs { 'origin/main', 'origin/master' } do
    if git { 'rev-parse', '--verify', b } then return b end
  end
end

vim.keymap.set('n', '<leader>gD', function()
  -- Toggle: if a Diffview tab is already open, close it instead of opening another.
  if require('diffview.lib').get_current_view() then
    vim.cmd 'DiffviewClose'
    return
  end
  local branch = default_branch()
  if not branch then
    vim.notify('No default branch found (origin/main or origin/master)', vim.log.levels.WARN)
    return
  end
  vim.cmd('DiffviewOpen ' .. branch .. '...HEAD')
end, { desc = '[G]it [D]iff vs default branch' })

vim.keymap.set('n', '<leader>gh', function()
  -- Toggle: if a Diffview tab is already open, close it instead of opening another.
  if require('diffview.lib').get_current_view() then
    vim.cmd 'DiffviewClose'
    return
  end
  vim.cmd 'DiffviewFileHistory %'
end, { desc = '[G]it file [H]istory' })

-- Same shortcut as gitsigns blame (<S-CR>): open the commit under the cursor in the browser.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'DiffviewFileHistory',
  callback = function(ev)
    vim.keymap.set('n', '<S-CR>', function()
      local view = require('diffview.lib').get_current_view()
      local entry = view and view.panel:get_log_entry_at_cursor()
      local hash = entry and entry.commit and entry.commit.hash
      if hash then
        require('custom.git_browser').open_commit(hash)
      else
        vim.notify('No commit under cursor', vim.log.levels.WARN)
      end
    end, { buffer = ev.buf, desc = 'Open commit in browser (<S-CR>)' })
  end,
})
