local M = {}

--- Resolve an ssh host through ~/.ssh/config. Remotes often use a per-account
--- alias (`git@github-personal:me/repo.git`); pasting that alias straight into
--- an https URL gives a host that doesn't resolve in a browser.
---@param host string
---@return string
local function real_host(host)
  local out = vim.fn.systemlist { 'ssh', '-G', host }
  if vim.v.shell_error ~= 0 then return host end
  for _, line in ipairs(out) do
    local hostname = line:match '^hostname (%S+)$'
    if hostname then return hostname end
  end
  return host
end

--- Anchor that scrolls a GitHub commit page to one line of one file's diff.
--- GitHub keys each file's diff on the sha256 of its path within that commit,
--- and suffixes the post-image line number with `R`.
---@param path string file path, relative to the repo root, as of that commit
---@param lnum integer line number within the file at that commit
---@return string
local function github_line_anchor(path, lnum) return ('#diff-%sR%d'):format(vim.fn.sha256(path), lnum) end

--- Open a commit on the remote's web UI (GitHub/GitLab/etc.) in the browser.
---@param hash string commit hash
---@param at? { path: string, lnum: integer } line to jump to, GitHub only
function M.open_commit(hash, at)
  local remote = vim.fn.system('git remote get-url origin 2>/dev/null'):gsub('%s+$', '')
  if remote == '' then
    vim.notify('No git remote found', vim.log.levels.WARN)
    return
  end
  local host, path = remote:match '^git@([^:]+):(.*)$'
  if host then remote = 'https://' .. real_host(host) .. '/' .. path end
  remote = remote:gsub('%.git$', '')

  local anchor = ''
  if at and remote:match 'github%.com' then anchor = github_line_anchor(at.path, at.lnum) end
  vim.ui.open(remote .. '/commit/' .. hash .. anchor)
end

return M
