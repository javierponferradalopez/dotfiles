local store = require 'ai-review.store'

local M = {}

local NS = vim.api.nvim_create_namespace 'ai-review'
local NS_FOCUS = vim.api.nvim_create_namespace 'ai-review-focus'

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

function M.focused_sign() return focused_icon(), SIGN_FOCUSED_HL end

local ICON_PRIORITY = 12

local COMMENT_BAR = '▎'
local CODE_BAR = '▏'
local NO_BAR = ' '
local COMMENT_BAR_HL = 'AIReviewBar'
local CODE_BAR_HL = 'AIReviewBarCode'

local SEARCH_WINDOW = 60
local MIN_SNIPPET = 4

local placed = {}
local synced = {}
local owner = {}

local open

local function resolve(buf)
  if not buf or buf == 0 then return vim.api.nvim_get_current_buf() end
  return buf
end

local function relocate(buf, comment)
  local total = vim.api.nvim_buf_line_count(buf)

  local function at(lnum)
    if lnum < 1 or lnum > total then return nil end
    return vim.trim(vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or '')
  end

  local want = vim.trim(comment.snippet or '')
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

local function span(buf, pair)
  local position = vim.api.nvim_buf_get_extmark_by_id(buf, NS, pair.range, { details = true })
  if not position[1] then return nil end

  local first = position[1]
  local last = position[3] and position[3].end_row or first

  return first + 1, math.max(last, first) + 1
end

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

local function virt_lines(buf, comment, lnum)
  local leading = (vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''):match '^%s*'
  local indent = (' '):rep(vim.fn.strdisplaywidth(leading))
  local width = math.max(40, vim.api.nvim_win_get_width(0) - #indent - 10)
  local lines = {}

  for _, chunk in ipairs(wrap(comment.text, width)) do
    table.insert(lines, { { indent .. chunk, 'AIReviewText' } })
  end

  return lines
end

local function orphaned_message(count)
  if count == 1 then return 'A review comment lost the code it was on -- :AIReviewList still has it' end

  return ('%d review comments lost the code they were on -- :AIReviewList still has them'):format(count)
end

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

local function innermost(first, size, id, best)
  if not best then return true end
  if first ~= best.first then return first > best.first end
  if size ~= best.size then return size < best.size end
  return id < best.id
end

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

  return store.get(best.id), best.first, best.first + best.size
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

function M.bar(buf, lnum, virtual)
  buf = resolve(buf)
  if not next(placed[buf] or {}) then return '' end
  if not block_at(buf, lnum) then return NO_BAR end

  if virtual then return '%#' .. COMMENT_BAR_HL .. '#' .. COMMENT_BAR .. '%*' end

  return '%#' .. CODE_BAR_HL .. '#' .. CODE_BAR .. '%*'
end

function M.gutter()
  local win = vim.g.statusline_winid
  local buf = (win and vim.api.nvim_win_is_valid(win)) and vim.api.nvim_win_get_buf(win) or vim.api.nvim_get_current_buf()

  return M.bar(buf, vim.v.lnum, vim.v.virtnum < 0)
end

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
