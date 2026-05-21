vim.pack.add { 'https://github.com/sindrets/diffview.nvim' }

require('diffview').setup {}

local function default_branch()
  local function git(args)
    local out = vim.fn.systemlist(vim.list_extend({ 'git' }, args))
    if vim.v.shell_error ~= 0 then return nil end
    return out[1]
  end

  local head_ref = git { 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD' }
  if head_ref then return head_ref:gsub('^origin/', '') end
  for _, b in ipairs { 'main', 'master' } do
    if git { 'rev-parse', '--verify', b } then return b end
  end
end

vim.keymap.set('n', '<leader>gD', function()
  local branch = default_branch()
  if not branch then
    vim.notify('No default branch found (main/master)', vim.log.levels.WARN)
    return
  end
  vim.cmd('DiffviewOpen ' .. branch .. '...HEAD')
end, { desc = '[G]it [D]iff vs default branch' })
