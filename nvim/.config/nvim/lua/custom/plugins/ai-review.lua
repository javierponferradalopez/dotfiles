-- Local, in-buffer code review for an AI agent. The implementation lives in
-- `lua/ai-review/`, ready to be lifted out into a plugin of its own; this file is
-- only the wiring the config needs.
--
-- Telescope (SECTION 4 of init.lua) provides the picker and is not re-added.

require('ai-review').setup()

local review = require 'ai-review'

vim.keymap.set('n', '<leader>aa', function() review.comment() end, { desc = '[A]I review comment [A]dd/edit' })

-- From visual mode the comment is anchored to the whole selection, so the agent
-- gets the region you meant instead of having to guess where it ends.
vim.keymap.set('v', '<leader>aa', function()
  -- Leave visual mode first: the '< and '> marks are only updated on exit.
  vim.cmd 'normal! \27'
  local first, last = vim.fn.line "'<", vim.fn.line "'>"
  vim.api.nvim_win_set_cursor(0, { first, 0 })
  review.comment(last)
end, { desc = '[A]I review comment [A]dd/edit' })

-- One comment goes with [D]elete, a set of them with [C]lear, and the widest wipe
-- of all -- the comments parked on the branches you are not on -- has no keymap at
-- all, only :AIReviewClearEverywhere. The header of `lua/ai-review/init.lua` says
-- why the words are kept apart.
vim.keymap.set('n', '<leader>ad', review.delete, { desc = '[A]I review [D]elete this comment' })
vim.keymap.set('n', '<leader>al', review.list, { desc = '[A]I review [L]ist comments' })
vim.keymap.set('n', '<leader>ac', review.clear_buffer, { desc = '[A]I review [C]lear this file' })
vim.keymap.set('n', '<leader>aC', review.clear_all, { desc = '[A]I review [C]lear all comments' })
