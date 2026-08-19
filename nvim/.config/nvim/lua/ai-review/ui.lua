local store = require 'ai-review.store'
local marks = require 'ai-review.marks'

local M = {}

local TITLE = 'AI-REVIEW'
local HEIGHT = 10
local SIGN_PRIORITY = 20
local NS = vim.api.nvim_create_namespace 'ai-review-compose'

local draft

local function bounds(available)
  local room = math.max(3, math.floor(available / 2))
  return math.min(HEIGHT, room), room
end

local function measure(buf, width)
  local rows = 0

  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    rows = rows + math.max(1, math.ceil((vim.fn.strdisplaywidth(line) + 1) / width))
  end

  return rows
end

local function fit(win, buf, host)
  local available = vim.api.nvim_win_get_height(win) + (vim.api.nvim_win_is_valid(host) and vim.api.nvim_win_get_height(host) or 0)
  local low, high = bounds(available)

  vim.api.nvim_win_set_height(win, math.max(low, math.min(measure(buf, vim.api.nvim_win_get_width(win)), high)))
end

local function spotlight(buf, first, last)
  if not first or not vim.api.nvim_buf_is_valid(buf) then return end

  local total = vim.api.nvim_buf_line_count(buf)
  if first > total then return end

  local glyph, hl = marks.focused_sign()

  vim.api.nvim_buf_set_extmark(buf, NS, first - 1, 0, {
    sign_text = glyph,
    sign_hl_group = hl,
    priority = SIGN_PRIORITY,
  })

  for row = first - 1, math.min(last or first, total) - 1 do
    vim.api.nvim_buf_set_extmark(buf, NS, row, 0, { line_hl_group = 'AIReviewDraft' })
  end
end

local function unspotlight(buf)
  if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1) end
end

local function reference(buf, line, extent)
  local name = vim.api.nvim_buf_get_name(buf)
  name = store.relpath(name) or vim.fn.fnamemodify(name, ':t')

  if not line then return name end
  if extent and extent > line then return ('%s:%d-%d'):format(name, line, extent) end

  return ('%s:%d'):format(name, line)
end

local function quoted(buf, line)
  if not line or not vim.api.nvim_buf_is_valid(buf) then return nil end

  local text = vim.trim(vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or '')
  if text == '' then return nil end

  return (text:gsub('%%', '%%%%'))
end

local function name_of(buf, about)
  if pcall(vim.api.nvim_buf_set_name, buf, 'ai-review://' .. about) then return end

  vim.api.nvim_buf_set_name(buf, ('ai-review://%s (%d)'):format(about, buf))
end

function M.drafting()
  if draft and vim.api.nvim_win_is_valid(draft) then return draft end

  draft = nil
  return nil
end

function M.focus()
  local win = M.drafting()
  if not win then return false end

  vim.api.nvim_set_current_win(win)
  return true
end

function M.compose(opts)
  local prev_win = vim.api.nvim_get_current_win()
  local target = vim.api.nvim_win_get_buf(prev_win)
  local layout = vim.fn.winrestcmd()
  local about = reference(target, opts.line, opts.extent)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].autoindent = false
  vim.bo[buf].buftype = 'acwrite'
  name_of(buf, about)

  if opts.text and opts.text ~= '' then vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.text, '\n')) end
  vim.bo[buf].modified = false

  local low = bounds(vim.api.nvim_win_get_height(prev_win))
  local win = vim.api.nvim_open_win(buf, true, { split = 'below', win = prev_win, height = low })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].statuscolumn = ''
  vim.wo[win].foldcolumn = '0'
  vim.wo[win].list = false

  local line = quoted(target, opts.line)
  vim.wo[win].winbar = (' %s · %s %s'):format(TITLE, about, line and ('%<· ' .. line .. ' ') or '')

  spotlight(target, opts.line, opts.extent)
  fit(win, buf, prev_win)

  draft = win

  local group = vim.api.nvim_create_augroup('ai-review-compose', { clear = true })

  local finished = false
  local function finish()
    if finished then return end
    finished = true
    draft = nil

    vim.schedule(function()
      unspotlight(target)

      if not vim.api.nvim_win_is_valid(win) then
        pcall(vim.cmd, layout)
        if vim.api.nvim_win_is_valid(prev_win) then vim.api.nvim_set_current_win(prev_win) end
      end

      opts.on_close()
    end)
  end

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = group,
    buffer = buf,
    callback = function()
      opts.on_confirm(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
      vim.bo[buf].modified = false
    end,
  })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = group,
    buffer = buf,
    callback = function()
      if not vim.api.nvim_win_is_valid(win) then return end
      fit(win, buf, prev_win)
    end,
  })

  vim.api.nvim_create_autocmd('WinLeave', {
    group = group,
    buffer = buf,
    callback = function() vim.schedule(function() vim.cmd 'stopinsert' end) end,
  })

  vim.api.nvim_create_autocmd('WinClosed', { group = group, pattern = tostring(win), once = true, callback = finish })
  vim.api.nvim_create_autocmd('BufWipeout', { group = group, buffer = buf, once = true, callback = finish })

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
