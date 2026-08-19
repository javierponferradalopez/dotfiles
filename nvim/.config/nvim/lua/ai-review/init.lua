local store = require 'ai-review.store'
local marks = require 'ai-review.marks'
local ui = require 'ai-review.ui'

local M = {}

local function highlights()
  local groups = {
    AIReviewSign = 'DiagnosticInfo',
    AIReviewSignFocused = 'AIReviewSign',
    AIReviewText = 'AIReviewSign',
    AIReviewBar = 'AIReviewSign',
    AIReviewBarCode = 'NonText',
  }

  for group, target in pairs(groups) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

local function counted(n) return n == 1 and '1 review comment' or ('%d review comments'):format(n) end

local function refresh(buffers)
  local gone = store.refresh()

  for _, buf in ipairs(buffers or { vim.api.nvim_get_current_buf() }) do
    marks.attach(buf)
  end

  marks.render_focus()

  if gone > 0 then vim.notify(counted(gone) .. ' done and deleted by the agent') end
end

function M.comment(last)
  local buf = vim.api.nvim_get_current_buf()
  local rel = store.relpath(vim.api.nvim_buf_get_name(buf))
  if not rel then
    vim.notify('This file is outside the project', vim.log.levels.WARN)
    return
  end

  refresh()

  local existing = marks.at_cursor()

  if existing then
    ui.compose {
      text = existing.text,
      on_confirm = function(text)
        text = vim.trim(text)
        if text == '' then return end
        existing.text = text
        store.touch(true)
        marks.attach(buf, true)
        marks.render_focus()
      end,
      on_delete = function()
        store.remove(existing.id)
        marks.attach(buf, true)
        marks.clear_focus(buf)
      end,
    }

    return
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1]

  ui.compose {
    on_confirm = function(text)
      text = vim.trim(text)
      if text == '' then return end

      store.add {
        path = rel,
        line = lnum,
        end_line = last and last > lnum and last or nil,
        snippet = vim.trim(vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''),
        text = text,
      }

      marks.attach(buf, true)
      marks.render_focus()
    end,
  }
end

function M.delete()
  local buf = vim.api.nvim_get_current_buf()

  refresh()

  local comment = marks.at_cursor()
  if not comment then
    vim.notify 'No review comment here'
    return
  end

  local quoted = vim.trim((comment.text:gsub('%s+', ' ')))
  if vim.fn.strdisplaywidth(quoted) > 60 then quoted = vim.fn.strcharpart(quoted, 0, 59) .. '…' end

  store.remove(comment.id)
  marks.attach(buf, true)
  marks.clear_focus(buf)

  vim.notify('Removed review comment: ' .. quoted)
end

function M.list()
  refresh(marks.buffers())
  ui.list()
end

function M.clear_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local rel = store.relpath(vim.api.nvim_buf_get_name(buf))
  if not rel then return end

  local removed = store.clear(rel)
  marks.attach(buf, true)
  marks.clear_focus(buf)

  vim.notify(removed > 0 and ('Removed ' .. counted(removed)) or 'No review comments in this file')
end

local function repaint()
  for _, buf in ipairs(marks.buffers()) do
    marks.attach(buf, true)
    marks.clear_focus(buf)
  end
end

function M.clear_all()
  local total = #store.comments()
  if total == 0 then
    vim.notify 'No review comments here'
    return
  end

  if vim.fn.confirm(('Remove all %s?'):format(counted(total)), '&Yes\n&No', 2) ~= 1 then return end

  local removed = store.clear(nil)
  repaint()

  vim.notify('Removed ' .. counted(removed))
end

function M.clear_everywhere()
  local total = store.total()
  if total == 0 then
    vim.notify 'No review comments anywhere'
    return
  end

  local prompt = ('Remove all %s, on this branch and on every other?'):format(counted(total))
  if vim.fn.confirm(prompt, '&Yes\n&No', 2) ~= 1 then return end

  local removed = store.clear_everywhere()
  repaint()

  vim.notify('Removed ' .. counted(removed))
end

M.gutter = marks.gutter

local GUTTER = [[%C%s%l%=%{%v:lua.require'ai-review'.gutter()%}]]

local function claim_gutter()
  if vim.o.statuscolumn ~= '' then return end

  vim.o.statuscolumn = GUTTER
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    vim.wo[win].statuscolumn = GUTTER
  end
end

local function jump(back)
  local buf = vim.api.nvim_get_current_buf()

  refresh()

  local spans = marks.spans(buf)
  if #spans == 0 then
    vim.notify 'No review comments in this file'
    return
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local target

  for _, entry in ipairs(spans) do
    if back and entry.first < row then
      target = entry.first
    elseif not back and entry.first > row then
      target = target or entry.first
    end
  end

  target = target or (back and spans[#spans].first or spans[1].first)

  vim.api.nvim_win_set_cursor(0, { target, 0 })
end

function M.next() jump(false) end
function M.prev() jump(true) end

function M.setup(opts)
  marks.configure(opts or {})

  claim_gutter()
  highlights()

  local group = vim.api.nvim_create_augroup('ai-review', { clear = true })

  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = highlights })

  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufEnter' }, {
    group = group,
    callback = function(ev) refresh { ev.buf } end,
  })

  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    callback = function() refresh(marks.buffers()) end,
  })

  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    callback = function(ev) marks.sync(ev.buf) end,
  })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'InsertLeave' }, {
    group = group,
    callback = function() marks.render_focus() end,
  })

  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    callback = function(ev) marks.clear_focus(ev.buf) end,
  })

  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function(ev) marks.forget(ev.buf) end,
  })

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      for _, buf in ipairs(marks.buffers()) do
        marks.sync(buf)
      end
    end,
  })

  vim.api.nvim_create_user_command('AIReviewList', M.list, { desc = 'List your AI review comments' })
  vim.api.nvim_create_user_command('AIReviewClearFile', M.clear_buffer, { desc = 'Remove the AI review comments in this file' })
  vim.api.nvim_create_user_command('AIReviewClearAll', M.clear_all, { desc = 'Remove all your AI review comments' })
  vim.api.nvim_create_user_command('AIReviewClearEverywhere', M.clear_everywhere, { desc = 'Remove all AI review comments, on this branch and on every other' })
end

return M
