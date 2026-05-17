local starter = require 'mini.starter'

local items = {
  { key = 'n', icon = '', desc = 'New File',     action = 'ene | startinsert' },
  { key = 'p', icon = '', desc = 'Sub-projects', action = function() SubProject.pick() end },
  { key = 't', icon = '', desc = 'Terminal',     action = 'split | term' },
  { key = 'c', icon = '', desc = 'Config',       action = function() require('telescope.builtin').find_files { cwd = vim.fn.stdpath 'config' } end },
  { key = 'q', icon = '', desc = 'Quit',         action = 'qa' },
}

starter.setup {
  header = '[ @javierponferradalopez ]',
  items = vim.tbl_map(function(it)
    return { name = it.key .. '  ' .. it.icon .. ' ' .. it.desc, action = it.action, section = '' }
  end, items),
  content_hooks = {
    starter.gen_hook.aligning('center', 'center'),
  },
  footer = '',
}

vim.api.nvim_create_autocmd('User', {
  pattern = 'MiniStarterOpened',
  callback = function(ev)
    for _, it in ipairs(items) do
      vim.keymap.set('n', it.key, function()
        if type(it.action) == 'function' then
          it.action()
        else
          vim.cmd(it.action)
        end
      end, { buffer = ev.buf, nowait = true, silent = true })
    end
  end,
})
