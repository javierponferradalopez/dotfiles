-- Local, in-buffer code review for an AI agent.
--
-- Drop `AI-REVIEW:` comments next to the code you want to discuss, keep coding,
-- and when you are done point the agent at them ("go through the AI-REVIEW
-- comments"). It greps them just like you do with <leader>al. Once the changes
-- are applied, <leader>ac wipes the markers out of the buffer and <leader>aC
-- out of the whole project.
--
-- Highlighting comes from todo-comments (the `AIREVIEW` keyword is registered
-- in init.lua, SECTION 3), so no plugin is added here.

local KEYWORD = 'AI-REVIEW'
-- Lua pattern used to find markers again: `-` is a quantifier, so escape it.
local MARKER_PATTERN = 'AI%-REVIEW:'

-- Render `comment` as a comment for the current filetype, indented like line
-- `lnum` (1-indexed) so the marker lines up with the code it refers to.
local function marker_line(comment, lnum)
  -- Split the commentstring instead of substituting into it: that keeps the
  -- comment out of gsub's replacement string (where `%` is special, so a plain
  -- `50%` would break it) and lets us normalise the spacing ourselves, since
  -- some filetypes ship `-- %s` and others `/*%s*/`. Filetypes without a
  -- commentstring still deserve a usable marker, hence the fallback.
  local prefix, suffix = vim.bo.commentstring:match '^(.*)%%s(.*)$'
  if not prefix then prefix, suffix = '#', '' end

  local text = vim.trim(prefix) .. ' ' .. KEYWORD .. ': ' .. comment
  if vim.trim(suffix) ~= '' then text = text .. ' ' .. vim.trim(suffix) end

  local indent = (vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ''):match '^%s*'

  return indent .. text
end

-- Ask for a comment and insert it as a marker above line `lnum`.
local function add_marker(lnum)
  vim.ui.input({ prompt = KEYWORD .. ': ' }, function(comment)
    if not comment or comment:match '^%s*$' then return end

    local line = marker_line(vim.trim(comment), lnum)
    vim.api.nvim_buf_set_lines(0, lnum - 1, lnum - 1, false, { line })
  end)
end

-- 1-indexed marker lines in `buf`, in descending order so callers can delete
-- them without invalidating the line numbers still pending.
local function marker_lines(buf)
  local hits = {}
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for i = #lines, 1, -1 do
    if lines[i]:find(MARKER_PATTERN) then table.insert(hits, i) end
  end

  return hits
end

-- Remove every marker line from `buf` and return how many went away.
local function clear_markers(buf)
  local hits = marker_lines(buf)

  for _, i in ipairs(hits) do
    vim.api.nvim_buf_set_lines(buf, i - 1, i, false, {})
  end

  return #hits
end

-- Every file holding a marker: what ripgrep finds on disk, plus any loaded
-- buffer whose markers have not been written yet (ripgrep cannot see those).
local function files_with_markers()
  local files, seen = {}, {}

  local function add(path)
    path = vim.fs.normalize(path)
    if path ~= '' and not seen[path] then
      seen[path] = true
      table.insert(files, path)
    end
  end

  if vim.fn.executable 'rg' == 1 then
    for _, path in ipairs(vim.fn.systemlist { 'rg', '--files-with-matches', '--fixed-strings', KEYWORD .. ':' }) do
      add(vim.fn.fnamemodify(path, ':p'))
    end
  else
    vim.notify('ripgrep not found: only checking loaded buffers', vim.log.levels.WARN)
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' and name ~= '' and #marker_lines(buf) > 0 then add(name) end
  end

  return files
end

-- Wipe the markers from the whole project, after confirming the blast radius.
local function clear_project()
  local files = files_with_markers()
  if #files == 0 then
    vim.notify('No ' .. KEYWORD .. ' markers in the project')
    return
  end

  if vim.fn.confirm(('Remove %s markers from %d file(s)?'):format(KEYWORD, #files), '&Yes\n&No', 2) ~= 1 then return end

  local removed, written, dirty = 0, 0, {}

  for _, path in ipairs(files) do
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)

    local had_pending_edits = vim.bo[buf].modified
    local n = clear_markers(buf)

    if n > 0 then
      removed = removed + n
      if had_pending_edits then
        -- Writing this buffer would also commit unrelated unsaved work, so drop
        -- the markers and leave the decision to save to the user.
        table.insert(dirty, vim.fn.fnamemodify(path, ':~:.'))
      else
        -- noautocmd: a formatter on BufWritePre would rewrite files the user
        -- never opened, which is well beyond what this keymap promises.
        vim.api.nvim_buf_call(buf, function()
          vim.cmd 'silent noautocmd write'
        end)
        written = written + 1
      end
    end
  end

  local msg = ('Removed %d %s marker(s), wrote %d file(s)'):format(removed, KEYWORD, written)
  if #dirty > 0 then msg = msg .. '; left unsaved (pending edits): ' .. table.concat(dirty, ', ') end
  vim.notify(msg)
end

vim.keymap.set('n', '<leader>aa', function()
  add_marker(vim.fn.line '.')
end, { desc = '[A]I review [A]dd marker' })

-- From visual mode the marker goes above the selection, so it reads as a note
-- about the whole block.
vim.keymap.set('v', '<leader>aa', function()
  -- Leave visual mode first: the '< mark is only updated on exit.
  vim.cmd 'normal! \27'
  add_marker(vim.fn.line "'<")
end, { desc = '[A]I review [A]dd marker' })

vim.keymap.set('n', '<leader>al', function()
  require('telescope.builtin').grep_string { search = KEYWORD .. ':', use_regex = false, prompt_title = 'AI review markers' }
end, { desc = '[A]I review [L]ist markers' })

vim.keymap.set('n', '<leader>ac', function()
  local removed = clear_markers(0)
  vim.notify(removed > 0 and ('Removed ' .. removed .. ' ' .. KEYWORD .. ' marker(s)') or ('No ' .. KEYWORD .. ' markers in this buffer'))
end, { desc = '[A]I review [C]lear buffer markers' })

vim.keymap.set('n', '<leader>aC', clear_project, { desc = '[A]I review [C]lear project markers' })

vim.api.nvim_create_user_command('AIReviewClear', function(opts)
  if opts.bang then
    clear_project()
  else
    clear_markers(0)
  end
end, { bang = true, desc = 'Remove AI-REVIEW markers from the current buffer (or the whole project with !)' })
