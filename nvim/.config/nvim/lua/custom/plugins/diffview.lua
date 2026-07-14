vim.pack.add { 'https://github.com/sindrets/diffview.nvim' }

-- Buffers already listed before Diffview was opened. On close we wipe only the
-- file buffers Diffview brought in (leaving the ones you already had open, and
-- any still visible in a window), so closing Diffview doesn't clutter the buffer
-- list with every file you inspected.
local pre_diffview_bufs = {}

local function snapshot_buffers()
  pre_diffview_bufs = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted then
      pre_diffview_bufs[b] = true
    end
  end
end

require('diffview').setup {
  hooks = {
    -- Diffview uses Vim's native diff folding (foldmethod=diff), which collapses
    -- unchanged lines. Disable folding in each diff window so the full file shows.
    diff_buf_win_enter = function(_, winid)
      vim.wo[winid].foldenable = false
      vim.wo[winid].foldlevel = 99
    end,
    view_closed = function()
      vim.schedule(function()
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if
            vim.api.nvim_buf_is_valid(b)
            and vim.bo[b].buflisted
            and not pre_diffview_bufs[b]
            and vim.fn.bufwinid(b) == -1
          then
            pcall(vim.api.nvim_buf_delete, b, {})
          end
        end
      end)
    end,
  },
}

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

vim.keymap.set('n', '<leader>gg', function()
  -- Toggle: if a Diffview tab is already open, close it instead of opening another.
  if require('diffview.lib').get_current_view() then
    vim.cmd 'DiffviewClose'
    return
  end
  -- No args: review all changed files in the working tree (staged + unstaged) vs HEAD.
  snapshot_buffers()
  vim.cmd 'DiffviewOpen'
end, { desc = '[G]it working tree diff' })

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
  snapshot_buffers()
  vim.cmd('DiffviewOpen ' .. branch .. '...HEAD')
end, { desc = '[G]it [D]iff vs default branch' })

vim.keymap.set('n', '<leader>gh', function()
  -- Toggle: if a Diffview tab is already open, close it instead of opening another.
  if require('diffview.lib').get_current_view() then
    vim.cmd 'DiffviewClose'
    return
  end
  snapshot_buffers()
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
