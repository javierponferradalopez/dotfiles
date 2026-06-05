local M = {}

--- Open a commit on the remote's web UI (GitHub/GitLab/etc.) in the browser.
---@param hash string commit hash
function M.open_commit(hash)
  local remote = vim.fn.system('git remote get-url origin 2>/dev/null'):gsub('%s+$', '')
  if remote == '' then
    vim.notify('No git remote found', vim.log.levels.WARN)
    return
  end
  remote = remote:gsub('^git@([^:]+):', 'https://%1/')
  remote = remote:gsub('%.git$', '')
  vim.ui.open(remote .. '/commit/' .. hash)
end

return M
