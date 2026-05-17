local MARKERS = { 'package.json', 'Cargo.toml', 'pyproject.toml', 'go.mod', 'composer.json' }
local EXCLUDES = "-not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' -not -path '*/.next/*'"

local function repo_root()
  local root = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')[1]
  return (root and root ~= '') and root or vim.fn.getcwd()
end

local function find_subprojects()
  local root = repo_root()
  local seen = {}
  local items = {}

  local name_clauses = {}
  for i, marker in ipairs(MARKERS) do
    if i > 1 then table.insert(name_clauses, '-o') end
    table.insert(name_clauses, string.format('-name %s', vim.fn.shellescape(marker)))
  end
  local cmd = string.format('find %s -maxdepth 4 \\( %s \\) %s', vim.fn.shellescape(root), table.concat(name_clauses, ' '), EXCLUDES)

  for _, path in ipairs(vim.fn.systemlist(cmd)) do
    local dir = vim.fn.fnamemodify(path, ':h')
    if dir ~= root and not seen[dir] then
      seen[dir] = true
      table.insert(items, {
        dir = dir,
        name = vim.fn.fnamemodify(dir, ':t'),
        rel = vim.fn.fnamemodify(dir, ':~:.'),
        marker = vim.fn.fnamemodify(path, ':t'),
      })
    end
  end

  table.sort(items, function(a, b) return a.rel < b.rel end)
  return items
end

local function pick()
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'

  local items = find_subprojects()
  if #items == 0 then
    vim.notify('No sub-projects found in this repo', vim.log.levels.WARN)
    return
  end

  pickers
    .new({}, {
      prompt_title = 'Sub-projects',
      finder = finders.new_table {
        results = items,
        entry_maker = function(item)
          local parent = vim.fn.fnamemodify(item.dir, ':~:.:h')
          return {
            value = item,
            display = item.name .. '  ' .. parent .. '  [' .. item.marker .. ']',
            ordinal = item.rel,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if not selection then return end
          local item = selection.value
          vim.fn.chdir(item.dir)
          vim.g.focused_subproject = item.name
          vim.notify('Focused: ' .. item.rel)
        end)
        return true
      end,
    })
    :find()
end

local function reset()
  local root = repo_root()
  vim.fn.chdir(root)
  vim.g.focused_subproject = nil
  vim.notify('Reset to: ' .. vim.fn.fnamemodify(root, ':~'))
end

SubProject = { pick = pick, reset = reset }

vim.keymap.set('n', '<leader>sp', pick, { desc = 'Focus Sub-project' })
vim.keymap.set('n', '<leader>sP', reset, { desc = 'Reset to repo root' })
