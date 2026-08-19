local store = require 'ai-review.store'

local M = {}

local TITLE = 'AI-REVIEW'

function M.compose(opts)
  local prev_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].autoindent = false

  if opts.text and opts.text ~= '' then vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.text, '\n')) end

  local width = math.min(80, vim.o.columns - 4)

  local rows = 1
  for _, line in ipairs(vim.split(opts.text or '', '\n')) do
    rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end

  local height = math.min(math.max(rows, 5), math.max(5, math.floor(vim.o.lines * 0.6)))

  local footer = opts.on_delete and ' <CR> save · <C-j> new line · <C-d> delete · <C-c>/q cancel ' or ' <CR> save · <C-j> new line · <C-c>/q cancel '

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = vim.o.winborder ~= '' and vim.o.winborder or 'rounded',
    title = ' ' .. TITLE .. ' ',
    title_pos = 'center',
    footer = footer,
    footer_pos = 'center',
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  local closed = false
  local function close()
    if closed then return end
    closed = true

    vim.cmd 'stopinsert'

    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_win_is_valid(prev_win) then vim.api.nvim_set_current_win(prev_win) end
  end

  local function confirm()
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    close()
    opts.on_confirm(text)
  end

  local function delete()
    close()
    opts.on_delete()
  end

  local function written() return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), ''):match '%S' ~= nil end

  local function escape()
    if not written() then
      close()
      return
    end

    if vim.fn.mode() == 'i' then vim.api.nvim_feedkeys(vim.keycode '<Esc>', 'n', false) end
  end

  vim.keymap.set({ 'n', 'i' }, '<CR>', confirm, { buffer = buf, desc = 'Save comment' })
  vim.keymap.set({ 'n', 'i' }, '<C-s>', confirm, { buffer = buf, desc = 'Save comment' })
  vim.keymap.set('i', '<C-j>', '<CR>', { buffer = buf, desc = 'New line' })
  vim.keymap.set('i', '<S-CR>', '<CR>', { buffer = buf, desc = 'New line' })
  vim.keymap.set('i', '<C-CR>', '<CR>', { buffer = buf, desc = 'New line' })
  vim.keymap.set('i', '<M-CR>', '<CR>', { buffer = buf, desc = 'New line' })
  vim.keymap.set('n', '<C-j>', 'o', { buffer = buf, desc = 'New line' })
  vim.keymap.set('n', '<S-CR>', 'o', { buffer = buf, desc = 'New line' })
  vim.keymap.set('n', '<C-CR>', 'o', { buffer = buf, desc = 'New line' })
  vim.keymap.set('n', '<M-CR>', 'o', { buffer = buf, desc = 'New line' })

  if opts.on_delete then vim.keymap.set({ 'n', 'i' }, '<C-d>', delete, { buffer = buf, desc = 'Delete comment' }) end

  vim.keymap.set({ 'n', 'i' }, '<C-c>', close, { buffer = buf, desc = 'Discard changes' })
  vim.keymap.set('n', 'q', close, { buffer = buf, desc = 'Discard changes' })
  vim.keymap.set({ 'n', 'i' }, '<Esc>', escape, { buffer = buf, desc = 'Leave insert, or close an untouched window' })

  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf,
    once = true,
    callback = function()
      if closed then return end
      if not written() then
        close()
        return
      end

      confirm()
    end,
  })

  if opts.text and opts.text ~= '' then
    vim.cmd 'normal! G$'
  else
    vim.cmd 'startinsert'
  end
end

local function one_line(text) return (text:gsub('%s+', ' ')) end

function M.list()
  local items = {}

  local function add(orphaned)
    for _, comment in ipairs(store.comments()) do
      if not comment.orphaned == not orphaned then
        table.insert(items, {
          filename = store.abspath(comment.path),
          lnum = comment.line,
          col = 1,
          text = orphaned and ('orphan · ' .. one_line(comment.text)) or one_line(comment.text),
        })
      end
    end
  end

  add(true)
  add(false)

  if #items == 0 then
    vim.notify 'Nothing to show'
    return
  end

  vim.fn.setqflist({}, ' ', { title = 'Review comments', items = items })
  vim.cmd 'copen'
end

return M
