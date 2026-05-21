vim.pack.add { 'https://github.com/uga-rosa/translate.nvim' }

require('translate').setup {
  default = {
    source = 'auto',
    target = 'es',
    output = 'floating',
  },
  preset = {
    output = {
      floating = { border = 'rounded' },
    },
  },
}

-- Normal mode: traduce la palabra bajo el cursor (<leader>tt para no chocar con el grupo Toggle)
vim.keymap.set('n', '<leader>tt', function()
  local word = vim.fn.expand '<cword>'
  local target = word:match '[áéíóúñÁÉÍÓÚÑ¿¡]' and 'en' or 'es'
  -- viw selects the word in visual; `:` auto-prepends `'<,'>` in command line
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('viw:Translate ' .. target .. '<CR>', true, false, true),
    'n', false
  )
end, { desc = '[T]ranslate word' })

-- Visual mode: traduce la selección (<leader>t, libre en visual)
-- Bidireccional: detecta caracteres españoles → traduce a EN; si no → traduce a ES
vim.keymap.set('v', '<leader>t', function()
  local s = vim.fn.getpos "'<"
  local e = vim.fn.getpos "'>"
  local lines = vim.api.nvim_buf_get_text(0, s[2] - 1, s[3] - 1, e[2] - 1, e[3], {})
  local text = table.concat(lines, ' ')
  local target = text:match '[áéíóúñÁÉÍÓÚÑ¿¡]' and 'en' or 'es'
  vim.cmd("'<,'>Translate " .. target)
end, { desc = '[T]ranslate' })
