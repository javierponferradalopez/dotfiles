-- What you look at: the window you write a comment in, and the list of them all.
--
-- Comments are prose, and the built-in cmdline prompt garbles anything longer
-- than the screen -- it scrolls sideways and leaves the redraw artefacts behind --
-- so they are composed in a floating scratch buffer instead. Since the text no
-- longer lives in the code, this one window is also where you read it, edit it
-- and delete it: `dd` and `ciw` are not available on something that was never
-- there.

local store = require 'ai-review.store'

local M = {}

local TITLE = 'AI-REVIEW'

-- Compose or edit a comment. `text` prefills the window, and `on_delete` -- given
-- only when there is something to delete -- puts <C-d> in the footer.
function M.compose(opts)
  local prev_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  -- Prose, not code: indentation carried over from the previous line would end up
  -- in the comment, and it is stored dedented anyway.
  vim.bo[buf].autoindent = false

  if opts.text and opts.text ~= '' then vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.text, '\n')) end

  local width = math.min(80, vim.o.columns - 4)

  local rows = 1
  for _, line in ipairs(vim.split(opts.text or '', '\n')) do
    rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end

  local height = math.min(math.max(rows, 5), math.max(5, math.floor(vim.o.lines * 0.6)))

  -- <C-j> rather than the <S-CR> you would rather press: it is the one that is
  -- always there to advertise. See the keymaps below for why.
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

  -- The whole point of the window: long comments wrap instead of scrolling away.
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  local closed = false
  local function close()
    if closed then return end
    closed = true

    -- This window puts you in insert mode, and the mode outlives it: without this
    -- you leave a draft and land back in your code typing into it. Every way out
    -- goes through here, so this is the one place that has to undo it. Nothing is
    -- being restored -- the keymaps that open this are normal- and visual-mode
    -- ones, so normal mode is where you were.
    vim.cmd 'stopinsert'

    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_win_is_valid(prev_win) then vim.api.nvim_set_current_win(prev_win) end
  end

  local function confirm()
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    -- Act on the original buffer, not the scratch one we are leaving.
    close()
    opts.on_confirm(text)
  end

  local function delete()
    close()
    opts.on_delete()
  end

  local function written() return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), ''):match '%S' ~= nil end

  -- The way out of a window you did not mean to open. Nothing written in it means
  -- nothing to lose, so <Esc> closes it rather than dropping you into normal mode
  -- in a window you have no use for. Once there is text, <Esc> is <Esc> again --
  -- fed back rather than a `stopinsert`, so the cursor lands where leaving insert
  -- mode leaves it -- or there would be no way to reach normal mode from here.
  local function escape()
    if not written() then
      close()
      return
    end

    if vim.fn.mode() == 'i' then vim.api.nvim_feedkeys(vim.keycode '<Esc>', 'n', false) end
  end

  -- Chat-like bindings: <CR> sends the comment, and breaking the line is the other
  -- key. Most review comments are one line long, which is what makes <CR> the
  -- right thing for it to do -- but it does mean the other key has to work.
  --
  -- <S-CR>, <C-CR> and <M-CR> are the ones worth pressing and none of them can be
  -- relied on: a terminal has to be told to send something for shift-and-return,
  -- and most are not, so all three arrive as a plain <CR> and save the comment you
  -- were trying to write the second line of. <C-j> is the newline character
  -- itself. Nothing has to be configured anywhere for it to arrive, which is why
  -- it is the one the footer names, and why the others are a convenience on top.
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

--------------------------------------------------------------------------- list

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
