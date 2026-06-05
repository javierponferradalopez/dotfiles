vim.pack.add { 'https://github.com/lewis6991/gitsigns.nvim' }

local git_browser = require 'custom.git_browser'

require('gitsigns').setup {
  on_attach = function(bufnr)
    local gs = require 'gitsigns'
    local map = function(l, r, desc)
      vim.keymap.set('n', l, r, { buffer = bufnr, desc = desc })
    end

    map(']c', function() gs.nav_hunk 'next' end, 'Next hunk')
    map('[c', function() gs.nav_hunk 'prev' end, 'Prev hunk')
    map('<leader>gb', function()
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'gitsigns-blame' then
          vim.api.nvim_win_close(w, false)
          return
        end
      end
      gs.blame()
    end, '[G]it [B]lame toggle')
    map('<leader>gd', gs.diffthis, '[G]it [D]iff')
  end,
}

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'gitsigns-blame',
  callback = function(ev)
    vim.keymap.set('n', '<S-CR>', function()
      local lnum = vim.fn.line '.'
      local orig_buf = nil
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(w)
        if vim.bo[buf].filetype ~= 'gitsigns-blame' then
          orig_buf = buf
          break
        end
      end
      if not orig_buf then return end
      local file = vim.api.nvim_buf_get_name(orig_buf)
      local hash = vim.fn.system(
        string.format('git blame -L %d,%d --porcelain %s 2>/dev/null | head -1', lnum, lnum, vim.fn.shellescape(file))
      ):match '^([0-9a-f]+)'
      if hash and #hash > 0 and not hash:match '^0+$' then
        git_browser.open_commit(hash)
      else
        vim.notify('No commit found for this line', vim.log.levels.WARN)
      end
    end, { buffer = ev.buf, desc = 'Open commit in browser (<S-CR>)' })
  end,
})
