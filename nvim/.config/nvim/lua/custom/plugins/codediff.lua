vim.pack.add { 'https://github.com/esmuellert/codediff.nvim' }

-- Buffers already listed before CodeDiff was opened. On close we wipe only the
-- file buffers CodeDiff brought in (leaving the ones you already had open, and
-- any still visible in a window), so closing a review doesn't clutter the buffer
-- list with every file you inspected.
local pre_diff_bufs = {}

local function snapshot_buffers()
  pre_diff_bufs = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted then pre_diff_bufs[b] = true end
  end
end

require('codediff').setup {
  diff = {
    -- Unified diff, the way a pull request reads: one pane per file with the
    -- deleted lines drawn above the change as virtual lines. Two side-by-side
    -- panes leave each version too cramped on a narrow screen; <leader>gl swaps
    -- back for the odd file that reads better in two.
    layout = 'inline',
  },
  explorer = {
    -- Files nested under their directories, not a flat list of full paths: in a
    -- monorepo the flat list is a wall of near-identical prefixes. Single-child
    -- directory chains stay collapsed (flatten_dirs defaults on), so the tree
    -- doesn't spend a row per level. `i` inside the panel toggles back to the
    -- flat list.
    view_mode = 'tree',
  },
  keymaps = {
    view = {
      -- These three defaults claim keys we already own: <leader>b opens the
      -- buffer group (bound nowait here, so it would fire before <leader>bd
      -- could complete), <leader>e toggles neo-tree, and `t` is the till
      -- motion. Rehome them under the git prefix, which is free inside a
      -- diff tab.
      toggle_explorer = '<leader>gp',
      focus_explorer = '<leader>ge',
      toggle_layout = '<leader>gl',
    },
  },
}

-- CodeDiff keys its sessions by tabpage, and only ever opens one at a time.
local function active_tabpage()
  local ok, session = pcall(require, 'codediff.ui.lifecycle.session')
  if not ok then return nil end
  for tabpage in pairs(session.get_active_diffs()) do
    if vim.api.nvim_tabpage_is_valid(tabpage) then return tabpage end
  end
end

-- Every binding below toggles: pressing it while a review is open closes that
-- review instead of stacking a second tab on top of it.
local function toggle(open)
  local tabpage = active_tabpage()
  if tabpage then
    require('codediff.ui.lifecycle').close(tabpage)
    return
  end
  snapshot_buffers()
  open()
end

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
  -- No args: review all changed files in the working tree (staged + unstaged) vs HEAD.
  toggle(function() vim.cmd 'CodeDiff' end)
end, { desc = '[G]it working tree diff' })

vim.keymap.set('n', '<leader>gD', function()
  toggle(function()
    local branch = default_branch()
    if not branch then
      vim.notify('No default branch found (origin/main or origin/master)', vim.log.levels.WARN)
      return
    end
    -- `a...b` is merge-base semantics: the changes this branch introduced, not
    -- the ones that landed on the base branch since it forked.
    vim.cmd('CodeDiff ' .. branch .. '...HEAD')
  end)
end, { desc = '[G]it [D]iff vs default branch' })

vim.keymap.set('n', '<leader>gh', function()
  toggle(function() vim.cmd 'CodeDiff history %' end)
end, { desc = '[G]it file [H]istory' })

vim.api.nvim_create_autocmd('User', {
  pattern = 'CodeDiffClose',
  callback = function()
    vim.schedule(function()
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted and not pre_diff_bufs[b] and vim.fn.bufwinid(b) == -1 then
          pcall(vim.api.nvim_buf_delete, b, {})
        end
      end
    end)
  end,
})

-- Open the commit under the cursor in the browser. <CR> is left alone here (it
-- opens the diff for the entry, which is more useful); <M-CR> is what a terminal
-- sending ESC+CR for Shift+Enter actually produces (see the Shift+Return binding
-- in alacritty.toml), while <S-CR> only arrives from terminals that speak the
-- CSI-u keyboard protocol.
vim.api.nvim_create_autocmd('User', {
  pattern = 'CodeDiffOpen',
  callback = function(ev)
    if not ev.data or ev.data.mode ~= 'history' then return end

    -- The history panel is stored as the tab's explorer, and its tree indexes
    -- nodes by line, so an argless get_node() is the entry under the cursor:
    -- either a commit row or one of the files inside it.
    local panel = require('codediff.ui.lifecycle').get_explorer(ev.data.tabpage)
    if not (panel and panel.bufnr and vim.api.nvim_buf_is_valid(panel.bufnr)) then return end

    local function open_commit()
      local node = panel.tree and panel.tree:get_node()
      local data = node and node.data
      local hash = data and (data.hash or data.commit_hash)
      if hash then
        require('custom.git_browser').open_commit(hash)
      else
        vim.notify('No commit under cursor', vim.log.levels.WARN)
      end
    end

    for _, lhs in ipairs { '<M-CR>', '<S-CR>' } do
      vim.keymap.set('n', lhs, open_commit, { buffer = panel.bufnr, desc = 'Open commit in browser' })
    end
  end,
})
