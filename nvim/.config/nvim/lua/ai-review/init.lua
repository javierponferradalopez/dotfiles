-- Local, in-buffer code review for an AI agent.
--
-- Leave a comment next to the code you want to discuss, keep coding, and when you
-- are done point the agent at them. The comment never enters the file: it lives in
-- `.ai-review/comments.json` at the project root, shows as a sign in the gutter,
-- and unfolds above the line when the cursor lands on it.
--
-- The store is the contract. `comments.json` holds the comments of the branch you
-- are on and carries its own protocol, so `CLAUDE.md` only has to say where it is.
--
-- The agent can do exactly one thing to a comment: delete it, once it has done what
-- the comment asked. There is no reply, no resolved state and no second file to
-- carry either -- with nothing to say back, saying it is deleting it. What it
-- changed, what it would not, what it did not follow, it tells you in the
-- conversation you are already having with it. A comment still on screen is one
-- still open between you, and it goes when you or the agent say so.
--
-- Deleting one and clearing many are deliberately different words. `ad` deletes the
-- comment in front of you, at once; `ac` and `aC` sweep a set you cannot see whole,
-- which is why the wider one stops to ask.
--
--   <leader>aa  write one here, or open the one here to read and edit it
--   <leader>ad  delete the one here            <leader>al  list them all
--   <leader>ac  drop this file's               <leader>aC  drop all of them
--
-- The store keeps a comment on the branch it was written on, so "all of them" is
-- all the ones you can see. The ones parked on the other branches are reached by
-- :AIReviewClearEverywhere, and by nothing else.

local store = require 'ai-review.store'
local marks = require 'ai-review.marks'
local ui = require 'ai-review.ui'

local M = {}

local function highlights()
  local groups = {
    AIReviewSign = 'DiagnosticInfo',
    AIReviewText = 'Comment',
  }

  for group, target in pairs(groups) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

-- Take in whatever the agent did to the store and repaint. Returns nothing:
-- everything it has to say, it says through the store and a notification.
local function refresh(buffers)
  local gone = store.refresh()

  for _, buf in ipairs(buffers or { vim.api.nvim_get_current_buf() }) do
    marks.attach(buf)
  end

  -- Said out loud because it happened off-screen: comments you wrote are missing
  -- from the margin now, and a count is the whole of what is left to tell.
  if gone > 0 then vim.notify(('%d AI review comment(s) done and deleted by the agent'):format(gone)) end
end

---------------------------------------------------------------------- the actions

-- The whole life cycle of one comment through one door. Nothing on this line
-- creates; something on it opens what is there, where <CR> saves the edit and
-- <C-d> deletes it.
function M.comment(last)
  local buf = vim.api.nvim_get_current_buf()
  local rel = store.relpath(vim.api.nvim_buf_get_name(buf))
  if not rel then
    vim.notify('ai-review: this file is outside the project', vim.log.levels.WARN)
    return
  end

  refresh()

  local existing = marks.at_cursor()

  if existing then
    ui.compose {
      text = existing.text,
      on_confirm = function(text)
        text = vim.trim(text)
        -- Emptying the window is not a way to delete: that is what <C-d> is for,
        -- and a comment lost to a stray `dG` would be unrecoverable.
        if text == '' then return end
        existing.text = text
        store.touch(true)
        marks.attach(buf, true)
        -- Re-attaching threw the decorations away, and the cursor has not moved:
        -- redraw so the edit shows now rather than the next time you move.
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

-- Delete the one comment you are looking at, with no window in the way. It does
-- not confirm and it does not need to: unlike the wipes below, what goes is the
-- thing on your screen, and it is quoted back to you as it goes.
function M.delete()
  local buf = vim.api.nvim_get_current_buf()

  refresh()

  local comment = marks.at_cursor()
  if not comment then
    vim.notify 'No AI review comment here'
    return
  end

  -- Flattened and cut by characters rather than bytes: the text is prose, and
  -- half a multibyte character in a message is a bug you only see in the message.
  local quoted = vim.trim((comment.text:gsub('%s+', ' ')))
  if vim.fn.strdisplaywidth(quoted) > 60 then quoted = vim.fn.strcharpart(quoted, 0, 59) .. '…' end

  store.remove(comment.id)
  marks.attach(buf, true)
  marks.clear_focus(buf)

  vim.notify('Removed AI review comment: ' .. quoted)
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

  vim.notify(removed > 0 and ('Removed %d AI review comment(s)'):format(removed) or 'No AI review comments in this file')
end

-- Repaint everything after a wipe: the comments went from the store, and the marks
-- standing in the buffers are the only thing that still thinks otherwise.
local function repaint()
  for _, buf in ipairs(marks.buffers()) do
    marks.attach(buf, true)
    marks.clear_focus(buf)
  end
end

function M.clear_all()
  local total = #store.comments()
  if total == 0 then
    vim.notify 'No AI review comments here'
    return
  end

  if vim.fn.confirm(('Remove all %d AI review comment(s)?'):format(total), '&Yes\n&No', 2) ~= 1 then return end

  local removed = store.clear(nil)
  repaint()

  vim.notify(('Removed %d AI review comment(s)'):format(removed))
end

-- Comments made on another branch are parked in the store and shown nowhere, so
-- this is the only thing that can reach them. It has no keymap on purpose: it
-- empties a drawer you cannot see into, and that is worth typing out.
function M.clear_everywhere()
  local total = store.total()
  if total == 0 then
    vim.notify 'No AI review comments anywhere'
    return
  end

  local prompt = ('Remove all %d AI review comment(s), on this branch and on every other?'):format(total)
  if vim.fn.confirm(prompt, '&Yes\n&No', 2) ~= 1 then return end

  local removed = store.clear_everywhere()
  repaint()

  vim.notify(('Removed %d AI review comment(s)'):format(removed))
end

-- One cell of gutter for the line being drawn: the bar of the block it belongs to,
-- or blank. Meant to be called from 'statuscolumn', which is the only way to put
-- something between the number column and the code. Wiring it up is the config's
-- call, not this module's: 'statuscolumn' is a global option, and a plugin has no
-- business rewriting the user's whole gutter.
M.gutter = marks.gutter

-------------------------------------------------------------------------- setup

function M.setup()
  highlights()

  local group = vim.api.nvim_create_augroup('ai-review', { clear = true })

  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = highlights })

  -- Reading the branch is a small file read and checking the store is a stat, so
  -- doing it on entry is cheaper than any machinery that would avoid it.
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufEnter' }, {
    group = group,
    callback = function(ev)
      refresh { ev.buf }
      marks.render_focus()
    end,
  })

  -- Coming back from the agent's window: this is the moment its deletions land.
  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    callback = function() refresh(marks.buffers()) end,
  })

  -- While the buffer was open the extmarks, not the stored line numbers, knew
  -- where the code went. Writing is when that gets committed to the store.
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    callback = function(ev) marks.sync(ev.buf) end,
  })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'InsertLeave' }, {
    group = group,
    callback = function() marks.render_focus() end,
  })

  -- A block of prose shifting the code down while you type is unusable.
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

  -- One command per thing that can be wiped, spelled out, rather than one command
  -- with a `!` that means something you have to remember: `:AIReviewClear<Tab>`
  -- should be able to tell you what each of them takes with it.
  vim.api.nvim_create_user_command('AIReviewList', M.list, { desc = 'List your AI review comments' })
  vim.api.nvim_create_user_command('AIReviewClearFile', M.clear_buffer, { desc = 'Remove the AI review comments in this file' })
  vim.api.nvim_create_user_command('AIReviewClearAll', M.clear_all, { desc = 'Remove all your AI review comments' })
  vim.api.nvim_create_user_command('AIReviewClearEverywhere', M.clear_everywhere, { desc = 'Remove all AI review comments, on this branch and on every other' })
end

return M
