vim.pack.add { 'https://github.com/chrisgrieser/nvim-rip-substitute' }
vim.keymap.set({ 'n', 'x' }, '<leader>fs', function()
  require('rip-substitute').sub()
end, { desc = ' rip substitute' })
