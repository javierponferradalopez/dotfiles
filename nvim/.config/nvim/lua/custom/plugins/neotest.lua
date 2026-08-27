vim.pack.add {
  'https://github.com/nvim-neotest/nvim-nio',
  'https://github.com/nvim-neotest/neotest',
  'https://github.com/marilari88/neotest-vitest',
}
-- Deps already present: plenary.nvim, nvim-treesitter

local vitest_util = require 'neotest-vitest.util'

-- Ordered by vitest's own config precedence.
local config_names = {
  'vitest.config.ts',
  'vitest.config.js',
  'vite.config.ts',
  'vite.config.js',
  'vitest.config.mts',
  'vitest.config.mjs',
  'vite.config.mts',
  'vite.config.mjs',
}

local function config_in(dir)
  for _, name in ipairs(config_names) do
    local candidate = vitest_util.path.join(dir, name)
    if vim.uv.fs_stat(candidate) then return candidate end
  end
end

-- Directories never worth walking when discovery is on.
local ignored_dirs = {
  node_modules = true,
  dist = true,
  build = true,
  coverage = true,
  ['.git'] = true,
  ['.next'] = true,
  ['.turbo'] = true,
}

local nearest_config_dir = vitest_util.root_pattern '{vite,vitest}.config.{js,ts,mjs,mts}'

-- Where vitest should run from. Prefer the package owning the file when it
-- carries its own config: in a monorepo the nearest config walking upwards is
-- often the root one, which declares every project, so running from there
-- boots the whole workspace to run a single test.
local function run_root(path)
  local pkg = vitest_util.find_package_json_ancestor(path)
  if pkg and config_in(pkg) then return pkg end
  return nearest_config_dir(path) or vitest_util.find_node_modules_ancestor(path)
end

require('neotest').setup {
  -- Discovery off: neotest only parses the buffers you open instead of walking
  -- every package in the monorepo. The summary panel then shows the files at
  -- hand, not thousands of unrelated tests.
  discovery = {
    enabled = false,
    concurrent = 1,
  },
  adapters = {
    require 'neotest-vitest' {
      vitestConfigFile = function(path)
        local dir = run_root(path)
        return dir and config_in(dir)
      end,
      cwd = run_root,
      filter_dir = function(name) return not ignored_dirs[name] end,
    },
  },
  summary = {
    follow = true, -- expand and follow the current file in the panel
    expand_errors = true, -- auto-expand failed positions
  },
}

local neotest = require 'neotest'

-- Open the summary panel and move focus into it, so the cursor lands on the
-- current file's tests (follow=true keeps it expanded on the active file).
local function focus_summary()
  neotest.summary.open()
  vim.schedule(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'neotest-summary' then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end)
end

-- [R]un group is registered in which-key inside init.lua (spec)
vim.keymap.set('n', '<leader>rt', function()
  neotest.run.run()
  focus_summary()
end, { desc = '[R]un [T]est nearest' })

vim.keymap.set('n', '<leader>rf', function()
  neotest.run.run(vim.fn.expand '%')
  focus_summary()
end, { desc = '[R]un test [F]ile' })

vim.keymap.set('n', '<leader>ro', function()
  focus_summary()
  neotest.output.open { enter = true }
end, { desc = '[R]un test [O]utput' })
