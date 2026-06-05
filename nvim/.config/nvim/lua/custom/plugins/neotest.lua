vim.pack.add {
  'https://github.com/nvim-neotest/nvim-nio',
  'https://github.com/nvim-neotest/neotest',
  'https://github.com/marilari88/neotest-vitest',
}
-- Deps already present: plenary.nvim, nvim-treesitter

require('neotest').setup {
  adapters = {
    require 'neotest-vitest',
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
