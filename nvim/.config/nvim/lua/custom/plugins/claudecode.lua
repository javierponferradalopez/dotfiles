vim.pack.add { 'https://github.com/coder/claudecode.nvim' }
require('claudecode').setup {}

vim.keymap.set('n', '<leader>cc', '<cmd>ClaudeCode<cr>', { desc = '[C]laude [C]ode toggle' })
vim.keymap.set('n', '<leader>cf', '<cmd>ClaudeCodeFocus<cr>', { desc = '[C]laude [F]ocus' })
vim.keymap.set('n', '<leader>cr', '<cmd>ClaudeCodeResume<cr>', { desc = '[C]laude [R]esume' })
vim.keymap.set('n', '<leader>cb', '<cmd>ClaudeCodeAdd %<cr>', { desc = '[C]laude add [B]uffer' })
vim.keymap.set('v', '<leader>cs', '<cmd>ClaudeCodeSend<cr>', { desc = '[C]laude [S]end selection' })
vim.keymap.set('n', '<leader>ca', '<cmd>ClaudeCodeDiffAccept<cr>', { desc = '[C]laude [A]ccept diff' })
vim.keymap.set('n', '<leader>cd', '<cmd>ClaudeCodeDiffDeny<cr>', { desc = '[C]laude [D]eny diff' })
