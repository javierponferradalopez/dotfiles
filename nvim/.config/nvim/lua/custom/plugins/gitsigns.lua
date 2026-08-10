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

-- Same shortcut as diffview file history (<S-CR>): open the commit under the
-- cursor in the browser.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'gitsigns-blame',
  callback = function(ev)
    -- Gitsigns opens the blame window as a vsplit off the file window, so right
    -- now the previous window is still the file being blamed. Capture it here:
    -- looking it up on keypress by scanning the tabpage picks whichever split
    -- comes first in the layout (neo-tree, another file, ...) instead.
    local src_buf = vim.api.nvim_win_get_buf(vim.fn.win_getid(vim.fn.winnr '#'))

    vim.keymap.set('n', '<S-CR>', function()
      -- The blame window has one line per line of the file and gitsigns keeps
      -- both scrollbound, so the cursor line indexes the blame entries directly.
      local ok, gs_cache = pcall(require, 'gitsigns.cache')
      local entry = ok and vim.tbl_get(gs_cache.cache, src_buf, 'blame', 'entries', vim.fn.line '.')
      local hash = entry and entry.commit and entry.commit.sha
      if hash and not hash:match '^0+$' then
        -- orig_lnum/filename locate the line *in that commit*, which is what the
        -- diff anchor needs: the file may have been renamed or shifted since.
        git_browser.open_commit(hash, { path = entry.filename, lnum = entry.orig_lnum })
      else
        vim.notify('No commit found for this line', vim.log.levels.WARN)
      end
    end, { buffer = ev.buf, desc = 'Open commit in browser (<S-CR>)' })
  end,
})
