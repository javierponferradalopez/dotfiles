-- What you look at: the window you write a comment in, and the picker.
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
  local height = math.min(10, math.max(5, math.floor(vim.o.lines * 0.25)))

  local footer = opts.on_delete and ' <CR> save · <S-CR> new line · <C-d> delete · <C-c>/q cancel ' or ' <CR> save · <S-CR> new line · <C-c>/q cancel '

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
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

  -- The way out of a window you did not mean to open. Nothing written in it means
  -- nothing to lose, so <Esc> closes it rather than dropping you into normal mode
  -- in a window you have no use for. Once there is text, <Esc> is <Esc> again --
  -- fed back rather than a `stopinsert`, so the cursor lands where leaving insert
  -- mode leaves it -- or there would be no way to reach normal mode from here.
  local function escape()
    if not table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), ''):match '%S' then
      close()
      return
    end

    if vim.fn.mode() == 'i' then vim.api.nvim_feedkeys(vim.keycode '<Esc>', 'n', false) end
  end

  -- Chat-like bindings: <CR> sends the comment, shift (or ctrl/alt, for terminals
  -- that do not tell <S-CR> apart) breaks the line.
  vim.keymap.set({ 'n', 'i' }, '<CR>', confirm, { buffer = buf, desc = 'Save comment' })
  vim.keymap.set({ 'n', 'i' }, '<C-s>', confirm, { buffer = buf, desc = 'Save comment' })
  vim.keymap.set('i', '<S-CR>', '<CR>', { buffer = buf, desc = 'New line' })
  vim.keymap.set('i', '<C-CR>', '<CR>', { buffer = buf, desc = 'New line' })
  vim.keymap.set('i', '<M-CR>', '<CR>', { buffer = buf, desc = 'New line' })
  vim.keymap.set('n', '<S-CR>', 'o', { buffer = buf, desc = 'New line' })
  vim.keymap.set('n', '<C-CR>', 'o', { buffer = buf, desc = 'New line' })
  vim.keymap.set('n', '<M-CR>', 'o', { buffer = buf, desc = 'New line' })

  if opts.on_delete then vim.keymap.set({ 'n', 'i' }, '<C-d>', delete, { buffer = buf, desc = 'Delete comment' }) end

  vim.keymap.set({ 'n', 'i' }, '<C-c>', close, { buffer = buf, desc = 'Discard changes' })
  vim.keymap.set('n', 'q', close, { buffer = buf, desc = 'Discard changes' })
  vim.keymap.set({ 'n', 'i' }, '<Esc>', escape, { buffer = buf, desc = 'Leave insert, or close an untouched window' })

  -- Clicking or jumping away discards the draft instead of leaking the window.
  vim.api.nvim_create_autocmd('BufLeave', { buffer = buf, once = true, callback = close })

  if opts.text and opts.text ~= '' then
    vim.cmd 'normal! G$'
  else
    vim.cmd 'startinsert'
  end
end

------------------------------------------------------------------------- picker

local function one_line(text) return (text:gsub('%s+', ' ')) end

-- The preview is the comment itself, whole and wrapped. The quickfix previewer
-- that came for free here showed the code at the line instead, which is the one
-- thing the comment is not and the one thing you are about to see anyway: the
-- text is what the list has to flatten into a line, so this is where it goes back
-- to being readable.
local function preview()
  local previewers = require 'telescope.previewers'

  return previewers.new_buffer_previewer {
    title = 'Comment',
    define_preview = function(self, entry)
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(entry.value.text, '\n'))
      vim.wo[self.state.winid].wrap = true
      vim.wo[self.state.winid].linebreak = true
    end,
  }
end

-- Every comment you have here. Orphans come first and say so: their line is a
-- last known position, so where it takes you is a hint, not the truth.
function M.list()
  local ordered = {}

  for _, comment in ipairs(store.comments()) do
    if comment.orphaned then table.insert(ordered, comment) end
  end
  for _, comment in ipairs(store.comments()) do
    if not comment.orphaned then table.insert(ordered, comment) end
  end

  if #ordered == 0 then
    vim.notify 'ai-review: nothing to show'
    return
  end

  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values

  -- Entries are built here rather than run through make_entry: the picker is a
  -- list of comments that happen to have a place, not of places, and `value` has
  -- to carry the comment for the preview to have anything to show.
  local function entry(comment)
    local where = ('%s:%d'):format(comment.path, comment.line)
    local label = one_line(comment.text)
    if comment.orphaned then label = 'orphan · ' .. label end

    return {
      value = comment,
      display = where .. '  ' .. label,
      ordinal = where .. ' ' .. comment.text,
      filename = store.abspath(comment.path),
      lnum = comment.line,
    }
  end

  pickers
    .new({}, {
      prompt_title = 'AI review comments',
      finder = finders.new_table { results = ordered, entry_maker = entry },
      previewer = preview(),
      sorter = conf.generic_sorter {},
    })
    :find()
end

return M
