vim.pack.add { 'https://github.com/javierponferradalopez/pickypen.nvim' }

local pickypen = require 'pickypen'

pickypen.setup()

vim.keymap.set({ 'n', 'v' }, '<leader>aa', pickypen.comment, { desc = '[A]nnotate [A]dd/edit' })
vim.keymap.set('n', '<leader>ad', pickypen.delete, { desc = '[A]nnotate [D]elete this comment' })
vim.keymap.set('n', '<leader>al', pickypen.list, { desc = '[A]nnotate [L]ist comments' })
vim.keymap.set('n', '<leader>ac', pickypen.clear_buffer, { desc = '[A]nnotate [C]lear this file' })
vim.keymap.set('n', '<leader>aC', pickypen.clear_all, { desc = '[A]nnotate [C]lear all comments' })

vim.keymap.set('n', ']a', pickypen.next, { desc = 'Next [A]nnotation' })
vim.keymap.set('n', '[a', pickypen.prev, { desc = 'Previous [A]nnotation' })
