-- The buffer side: where each comment is right now, and what you see of it.
--
-- Two extmarks per comment, and neither of them is redundant. The range mark spans
-- the code the comment is about and draws nothing; the anchor mark sits on its
-- first line and carries the icon. One ranged extmark with an icon would stamp that
-- icon on every line of the range, which says a comment exists but nothing about
-- how far it reaches. Both track the text natively, so nothing is repainted as you
-- edit.
--
-- The block you read when the cursor is inside it is a throwaway decoration in its
-- own namespace: it holds no state, so it can be wiped and redrawn at will. The one
-- thing focus does reach into is the anchor's glyph, which opens from a filled dot
-- to a hollow one while you are reading -- an edit to the sign the comment already
-- has rather than a second sign over it, for the reason given where they are
-- defined. It is the only writing to the anchors that does not come from attach().
--
-- A comment whose anchor cannot be found again is orphaned, and an orphan is
-- deliberately not drawn anywhere: painting it at its last known line is exactly
-- the wrong-place guess this design refuses to make.

local store = require 'ai-review.store'

local M = {}

local NS = vim.api.nvim_create_namespace 'ai-review'
local NS_FOCUS = vim.api.nvim_create_namespace 'ai-review-focus'

-- The icon is an ordinary sign, so it sits wherever signs sit: out on the left of
-- the number column, lined up with the git and diagnostic signs. Glyph then space,
-- because a bare glyph butts against whatever is drawn next to it.
--
-- A filled dot at rest, hollow while you are reading it. Geometric shapes rather
-- than a Nerd Font glyph: an icon is the whole of what this draws in the margin,
-- and a missing font turns the whole of it into a box. These two are in the fonts
-- people already have.
--
-- The pair is deliberately one shape in two states, not two icons. Focus opens the
-- dot up rather than colouring it, so the margin reads at a glance and reads the
-- same to someone who cannot tell the two colours apart.
local SIGN = '● '
local SIGN_FOCUSED = '○ '
local SIGN_HL = 'AIReviewSign'
local SIGN_FOCUSED_HL = 'AIReviewSignFocused'

local configured = {}

local function icon() return configured.sign or SIGN end
local function focused_icon() return configured.sign_focused or SIGN_FOCUSED end

function M.configure(opts)
  configured.sign = opts.sign
  configured.sign_focused = opts.sign_focused
end

-- Above the default sign priority so a comment is not hidden by a git change on
-- the same line. Signs on a line are ordered by priority and only the highest fits
-- a one-column 'signcolumn'.
local ICON_PRIORITY = 12

-- The bar is NOT a sign: a sign would land out on the left with the icon, far from
-- the code, and it would fight gitsigns for the one sign cell. It gets its own cell
-- immediately before the text, drawn by 'statuscolumn' (see M.gutter). A left block
-- leaves its own breathing room inside the cell, so one cell is enough.
--
-- One bar runs through the comment and the code below it, so they read as one
-- block, and the weight says which is which: the full weight goes to what you
-- wrote, the light one to the code it points at. The comment is the thing being
-- said; the code is the thing being pointed at.
local COMMENT_BAR = '▎'
local CODE_BAR = '▏'
local NO_BAR = ' '
local COMMENT_BAR_HL = 'AIReviewBar'
local CODE_BAR_HL = 'AIReviewBarCode'

-- How far to look for an anchor that moved while the buffer was closed. Wide
-- enough for ordinary edits above it, narrow enough that a match found this far
-- away is still plausibly the same code.
local SEARCH_WINDOW = 60
-- A snippet with less than this much substance ('}', 'end', '') matches almost
-- everywhere, so it is not evidence of anything: such a comment is orphaned
-- rather than re-anchored to whichever '}' happened to be nearest.
local MIN_SNIPPET = 4

-- The extmark pair of each comment placed in a buffer, the store generation they
-- were placed from, and the way back from a range extmark to the comment that owns
-- it -- which is what lets the gutter answer "is this line inside a block?" from
-- an extmark lookup instead of a scan.
local placed = {}
local synced = {}
local owner = {}

-- The anchor currently standing open, so it can be closed again when the cursor
-- leaves it. One entry rather than a set, because only one comment is ever
-- focused -- and it carries its buffer, since the cursor can leave by moving to
-- another one entirely.
local open

-- Every API call takes 0 to mean "the current buffer", so callers pass it. As a
-- table key, though, 0 is not the buffer it stands for, and state filed under it
-- would be written in one place and read in another. Resolve it once, at the door.
local function resolve(buf)
  if not buf or buf == 0 then return vim.api.nvim_get_current_buf() end
  return buf
end

------------------------------------------------------------------- re-anchoring

-- Where did this comment's anchor go? The stored line is only trusted when the
-- code sitting there still matches the snippet; otherwise we search outward from
-- it. `nil` means we could not tell, which the caller turns into an orphan.
local function relocate(buf, comment)
  local total = vim.api.nvim_buf_line_count(buf)

  local function at(lnum)
    if lnum < 1 or lnum > total then return nil end
    return vim.trim(vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or '')
  end

  local want = vim.trim(comment.snippet or '')
  -- Nothing to recognise it by (a comment on a blank line, or an older entry):
  -- the line number is all we have, so take it if it still exists.
  if want == '' then return comment.line <= total and comment.line or nil end

  if at(comment.line) == want then return comment.line end
  if #want:gsub('%s', '') < MIN_SNIPPET then return nil end

  for delta = 1, SEARCH_WINDOW do
    if at(comment.line - delta) == want then return comment.line - delta end
    if at(comment.line + delta) == want then return comment.line + delta end
  end

  return nil
end

local function place(buf, comment, lnum)
  local total = vim.api.nvim_buf_line_count(buf)
  local last = math.max(math.min(comment.end_line or lnum, total), lnum)

  local range = vim.api.nvim_buf_set_extmark(buf, NS, lnum - 1, 0, {
    end_row = last - 1,
    end_right_gravity = true,
  })

  owner[buf] = owner[buf] or {}
  owner[buf][range] = comment.id

  return {
    range = range,
    anchor = vim.api.nvim_buf_set_extmark(buf, NS, lnum - 1, 0, {
      sign_text = icon(),
      sign_hl_group = SIGN_HL,
      priority = ICON_PRIORITY,
    }),
  }
end

-- Where a comment's block currently begins and ends, 1-indexed, according to its
-- range mark rather than to whatever the store last wrote down.
local function span(buf, pair)
  local position = vim.api.nvim_buf_get_extmark_by_id(buf, NS, pair.range, { details = true })
  if not position[1] then return nil end

  local first = position[1]
  local last = position[3] and position[3].end_row or first

  return first + 1, math.max(last, first) + 1
end

------------------------------------------------------------------------- render

-- Measured in display cells rather than bytes: `#word` is the length of an
-- encoding, and for anything but ASCII it is not the width of anything. Wrapping
-- on it breaks the block short for every accent and every CJK character in it, so
-- the running width is carried alongside the line instead of remeasuring it.
local function wrap(text, width)
  local out = {}

  for _, paragraph in ipairs(vim.split(text, '\n')) do
    local line, used = '', 0

    for word in paragraph:gmatch '%S+' do
      local size = vim.fn.strdisplaywidth(word)

      if line == '' then
        line, used = word, size
      elseif used + size + 1 <= width then
        line, used = line .. ' ' .. word, used + size + 1
      else
        table.insert(out, line)
        line, used = word, size
      end
    end

    table.insert(out, line)
  end

  return out
end

-- The block drawn above the code: what you wrote, and only that. Indented like the
-- line it opens, so it lines up with the code it is about. Nothing marks it as a
-- comment here -- that is the thin bar's job, drawn in the gutter cell alongside
-- these lines, which keeps it in the same column as the bar down the code instead
-- of one cell adrift inside the content.
local function virt_lines(buf, comment, lnum)
  -- Copied as the spaces it displays as, not verbatim: virtual text does not
  -- expand a tab, so carrying one over would leave the block adrift from the code
  -- it is supposed to line up with in every tab-indented file there is.
  local leading = (vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''):match '^%s*'
  local indent = (' '):rep(vim.fn.strdisplaywidth(leading))
  local width = math.max(40, vim.api.nvim_win_get_width(0) - #indent - 10)
  local lines = {}

  for _, chunk in ipairs(wrap(comment.text, width)) do
    table.insert(lines, { { indent .. chunk, 'AIReviewText' } })
  end

  return lines
end

---------------------------------------------------------------------- public API

local function orphaned_message(count)
  if count == 1 then return 'A review comment lost the code it was on -- :AIReviewList still has it' end

  return ('%d review comments lost the code they were on -- :AIReviewList still has them'):format(count)
end

-- Re-anchor every comment for this buffer and place its marks. Called on read and
-- on entry, but it only redoes the work when the store has actually moved on.
function M.attach(buf, force)
  buf = resolve(buf)
  if not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].buftype ~= '' then return end

  local rel = store.relpath(vim.api.nvim_buf_get_name(buf))
  if not rel then return end

  local generation = store.generation()
  if not force and synced[buf] == generation then return end

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  placed[buf] = {}
  owner[buf] = {}
  -- The anchors are being thrown away and replaced, so anything standing open went
  -- with them. Forget it rather than leave a closing edit aimed at an id that is no
  -- longer there; the next render_focus opens whichever anchor replaced it.
  if open and open.buf == buf then open = nil end

  local changed = false
  local lost = 0

  for _, comment in ipairs(store.for_path(rel)) do
    local lnum = relocate(buf, comment)

    if lnum then
      if comment.line ~= lnum or comment.orphaned then changed = true end
      comment.line = lnum
      comment.orphaned = nil
      placed[buf][comment.id] = place(buf, comment, lnum)
    elseif not comment.orphaned then
      comment.orphaned = true
      changed = true
      lost = lost + 1
    end
  end

  if changed then store.touch(true) end
  if lost > 0 then vim.notify(orphaned_message(lost), vim.log.levels.WARN) end
  synced[buf] = store.generation()
end

-- Read the marks back into the store: while the buffer was open they, not the
-- stored line numbers, knew where the code went.
function M.sync(buf)
  buf = resolve(buf)
  local marks = placed[buf]
  if not marks then return end
  if not store.relpath(vim.api.nvim_buf_get_name(buf)) then return end

  local changed = false

  for id, pair in pairs(marks) do
    local comment = store.get(id)
    local first, last = span(buf, pair)

    if comment and first then
      local snippet = vim.trim(vim.api.nvim_buf_get_lines(buf, first - 1, first, false)[1] or '')

      if comment.line ~= first or comment.snippet ~= snippet then changed = true end
      comment.line = first
      comment.snippet = snippet
      comment.end_line = last > first and last or nil
    end
  end

  if changed then store.touch(true) end
  synced[buf] = store.generation()
end

-- Which of two blocks over the cursor is the one you mean. Innermost first: the
-- one that starts later, and on a tie the shorter one -- comparing the start alone
-- cannot tell 10-20 from 10-12, which is the pair the word "innermost" is about.
-- The id settles what is left, because two comments really can share both ends
-- (the store is also written by the agent, and re-anchoring can walk two of them
-- onto the same line) and `pairs` would otherwise hand back a different one of
-- them on every call. Ids begin with the time they were written, so the tie goes
-- to the older comment and goes there for good.
local function innermost(first, size, id, best)
  if not best then return true end
  if first ~= best.first then return first > best.first end
  if size ~= best.size then return size < best.size end
  return id < best.id
end

-- The comment whose block the cursor is inside -- not merely the line it is
-- anchored to. A range comment is about all of its lines, so all of them show it.
-- Returns the comment and the first line of its block.
function M.at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local best

  for id, pair in pairs(placed[buf] or {}) do
    local first, last = span(buf, pair)

    if first and row >= first and row <= last then
      local size = last - first
      if innermost(first, size, id, best) then best = { first = first, size = size, id = id } end
    end
  end

  if not best then return nil end

  return store.get(best.id), best.first
end

function M.spans(buf)
  buf = resolve(buf)
  local found = {}

  for id, pair in pairs(placed[buf] or {}) do
    local first, last = span(buf, pair)
    if first then table.insert(found, { first = first, last = last, id = id }) end
  end

  table.sort(found, function(a, b)
    if a.first ~= b.first then return a.first < b.first end
    return a.id < b.id
  end)

  return found
end

-- Swap the glyph on an anchor, in place. Opening the dot is an edit to the one
-- sign the comment already has, not a second sign laid over it: signs do not stack
-- but queue, so on a 'signcolumn' with room for two the hollow one would end up
-- sitting next to the filled one rather than replacing it.
--
-- This is the one thing that writes to NS outside attach(), and it writes nothing
-- the store cares about -- same id, same position, a different glyph.
local function restamp(buf, id, glyph, hl)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local position = vim.api.nvim_buf_get_extmark_by_id(buf, NS, id, {})
  if not position[1] then return end

  vim.api.nvim_buf_set_extmark(buf, NS, position[1], 0, {
    id = id,
    sign_text = glyph,
    sign_hl_group = hl,
    priority = ICON_PRIORITY,
  })
end

local function close_open()
  if not open then return end

  restamp(open.buf, open.id, icon(), SIGN_HL)
  open = nil
end

-- Draw the focused comment, wiping whatever was drawn before. Cheap enough to run
-- on every cursor move: a namespace clear, and at most one extmark drawn, one
-- anchor opened and one closed.
function M.render_focus()
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(buf, NS_FOCUS, 0, -1)

  local comment, lnum = M.at_cursor()
  local pair = comment and (placed[buf] or {})[comment.id]
  local anchor = pair and pair.anchor

  if open and (open.buf ~= buf or open.id ~= anchor) then close_open() end

  if not comment then return end

  if anchor and not open then
    restamp(buf, anchor, focused_icon(), SIGN_FOCUSED_HL)
    open = { buf = buf, id = anchor }
  end

  -- Above the first line of the block, wherever in it the cursor happens to be:
  -- the comment belongs to the code it opens, and it should not shuffle up and
  -- down as you move through the block.
  vim.api.nvim_buf_set_extmark(buf, NS_FOCUS, lnum - 1, 0, {
    virt_lines = virt_lines(buf, comment, lnum),
    virt_lines_above = true,
  })
end

function M.clear_focus(buf)
  buf = resolve(buf)
  close_open()
  if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_clear_namespace(buf, NS_FOCUS, 0, -1) end
end

------------------------------------------------------------------------- gutter

-- The comment whose block covers `lnum` in `buf`, if any. `overlap` is what makes
-- this one lookup rather than a scan: without it a ranged extmark is only found at
-- the line it starts on, and every line of a block has to ask about every comment.
local function block_at(buf, lnum)
  local row = lnum - 1
  local hits = vim.api.nvim_buf_get_extmarks(buf, NS, { row, 0 }, { row, -1 }, { overlap = true })
  local index = owner[buf] or {}

  for _, mark in ipairs(hits) do
    local id = index[mark[1]]
    if id then
      local comment = store.get(id)
      if comment then return comment end
    end
  end
end

-- One cell of gutter, to be placed by 'statuscolumn' right before the code. This
-- module only answers what belongs in that cell for the line being drawn.
--
-- `virtual` marks the rows that hold the comment text itself, which get the full
-- weight; the code the comment points at gets the light one. Nothing is drawn
-- inside the text -- the weight carries that meaning, and a marker in the prose is
-- what made it read as a banner.
function M.bar(buf, lnum, virtual)
  buf = resolve(buf)
  if not next(placed[buf] or {}) then return '' end
  if not block_at(buf, lnum) then return NO_BAR end

  if virtual then return '%#' .. COMMENT_BAR_HL .. '#' .. COMMENT_BAR .. '%*' end

  return '%#' .. CODE_BAR_HL .. '#' .. CODE_BAR .. '%*'
end

-- The 'statuscolumn' entry point: same answer as M.bar, with everything read off
-- the row being drawn. v:virtnum is negative on a virtual line (the comment) and
-- positive on the wrapped remainder of a real one, which is still code and so keeps
-- the code weight.
function M.gutter()
  local win = vim.g.statusline_winid
  local buf = (win and vim.api.nvim_win_is_valid(win)) and vim.api.nvim_win_get_buf(win) or vim.api.nvim_get_current_buf()

  return M.bar(buf, vim.v.lnum, vim.v.virtnum < 0)
end

-- Every loaded buffer that could be holding marks, for the paths that act on all
-- of them at once (a refresh, or leaving Neovim).
function M.buffers()
  local found = {}

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' and vim.api.nvim_buf_get_name(buf) ~= '' then table.insert(found, buf) end
  end

  return found
end

function M.forget(buf)
  buf = resolve(buf)
  placed[buf] = nil
  synced[buf] = nil
  owner[buf] = nil
  if open and open.buf == buf then open = nil end
end

return M
