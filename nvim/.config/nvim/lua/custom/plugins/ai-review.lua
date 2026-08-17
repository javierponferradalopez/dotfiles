-- Local, in-buffer code review for an AI agent.
--
-- Drop `AI-REVIEW:` comments next to the code you want to discuss, keep coding,
-- and when you are done point the agent at them ("go through the AI-REVIEW
-- comments"). It greps them just like you do with <leader>al, applies the
-- obvious ones once you approve the list, talks the rest through one by one,
-- and deletes each marker as it settles it. <leader>ac and <leader>aC wipe the
-- markers by hand, from the buffer or the whole project.
--
-- Comments are written in a floating window rather than the cmdline, which
-- cannot render long prose. <CR> saves and <S-CR> breaks the line, as in a chat
-- prompt. A comment that spans several lines keeps the keyword on the first one
-- only and continues on the plain comment lines below it.
--
-- Highlighting comes from todo-comments (the `AIREVIEW` keyword is registered
-- in init.lua, SECTION 3), so no plugin is added here.

local KEYWORD = 'AI-REVIEW'
-- Lua pattern used to find markers again: `-` is a quantifier, so escape it.
local MARKER_PATTERN = 'AI%-REVIEW:'
-- A marker longer than one line continues on plain comment lines, padded so the
-- text lines up under the first one. That padding is not decoration: it is what
-- tells a continuation apart from an ordinary comment when clearing the marker.
local CONTINUATION = string.rep(' ', #KEYWORD + 2)

-- The comment delimiters for `buf`'s filetype, already trimmed.
--
-- Split the commentstring instead of substituting into it: that keeps the draft
-- out of gsub's replacement string (where `%` is special, so a plain `50%` would
-- break it) and lets us normalise the spacing ourselves, since some filetypes
-- ship `-- %s` and others `/*%s*/`. Filetypes without a commentstring still
-- deserve a usable marker, hence the fallback.
local function comment_parts(buf)
  local prefix, suffix = vim.bo[buf].commentstring:match '^(.*)%%s(.*)$'
  if not prefix then prefix, suffix = '#', '' end

  return vim.trim(prefix), vim.trim(suffix)
end

-- Split the draft into the lines it will keep in the buffer: trailing whitespace
-- and blank lines go, and the block is dedented, so whatever indentation is left
-- is the one that was meant (a list, a snippet) rather than the popup's.
local function draft_lines(draft)
  local lines = {}

  for _, line in ipairs(vim.split(draft, '\n')) do
    line = line:gsub('%s+$', '')
    if line ~= '' then table.insert(lines, line) end
  end

  local common = math.huge
  for _, line in ipairs(lines) do
    common = math.min(common, #line:match '^%s*')
  end

  for i, line in ipairs(lines) do
    lines[i] = line:sub(common + 1)
  end

  return lines
end

-- Render `draft` as comments for `buf`'s filetype, indented like line `lnum`
-- (1-indexed) so the marker lines up with the code it refers to. Only the first
-- line carries the keyword; the rest are plain comments padded to line up under
-- it, so one marker is one hit when listing them.
local function marker_block(draft, lnum, buf)
  local prefix, suffix = comment_parts(buf)
  local indent = (vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''):match '^%s*'

  local markers = {}

  for i, text in ipairs(draft_lines(draft)) do
    local body = i == 1 and (KEYWORD .. ': ' .. text) or (CONTINUATION .. text)
    local line = indent .. prefix .. ' ' .. body
    if suffix ~= '' then line = line .. ' ' .. suffix end
    table.insert(markers, line)
  end

  return markers
end

-- Floating scratch buffer to compose a comment in. These markers are prose, and
-- the built-in cmdline prompt garbles anything longer than the screen: it
-- scrolls sideways and leaves the redraw artefacts behind.
local function open_draft_window(on_confirm)
  local prev_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  -- Prose, not code: indentation carried over from the previous line would end
  -- up in the marker, and the draft is inserted with its own indentation anyway.
  vim.bo[buf].autoindent = false

  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(10, math.max(5, math.floor(vim.o.lines * 0.25)))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. KEYWORD .. ' ',
    title_pos = 'center',
    footer = ' <CR> save · <S-CR> new line · <C-c>/q cancel ',
    footer_pos = 'center',
  })

  -- The whole point of the window: long comments wrap instead of scrolling away.
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  local closed = false
  local function close()
    if closed then return end
    closed = true

    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_win_is_valid(prev_win) then vim.api.nvim_set_current_win(prev_win) end
  end

  local function confirm()
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    -- Insert into the original buffer, not the scratch one we are leaving.
    close()
    on_confirm(text)
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

  vim.keymap.set({ 'n', 'i' }, '<C-c>', close, { buffer = buf, desc = 'Discard comment' })
  vim.keymap.set('n', 'q', close, { buffer = buf, desc = 'Discard comment' })

  -- Clicking or jumping away discards the draft instead of leaking the window.
  vim.api.nvim_create_autocmd('BufLeave', { buffer = buf, once = true, callback = close })

  vim.cmd 'startinsert'
end

-- Ask for a comment and insert it as a marker above line `lnum`.
local function add_marker(lnum)
  local buf = vim.api.nvim_get_current_buf()

  open_draft_window(function(draft)
    local markers = marker_block(draft, lnum, buf)
    if #markers == 0 then return end

    vim.api.nvim_buf_set_lines(buf, lnum - 1, lnum - 1, false, markers)
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

-- Remove every marker from `buf`, continuation lines included, and return how
-- many went away.
local function clear_markers(buf)
  local hits = marker_lines(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Descending, so deleting a marker leaves the earlier line numbers untouched.
  for _, first in ipairs(hits) do
    -- Everything before the keyword — indent and comment prefix — read off the
    -- marker itself rather than the buffer's commentstring, which may have been
    -- lost (no filetype) or changed since the marker was written. A continuation
    -- repeats it and then pushes its text right; an ordinary comment starts one
    -- space after the prefix, so a stray comment below a marker is left alone.
    local lead = lines[first]:sub(1, lines[first]:find(MARKER_PATTERN) - 1)
    local continuation = '^' .. vim.pesc(lead) .. '  +%S'

    local last = first
    while lines[last + 1] and lines[last + 1]:match(continuation) do
      last = last + 1
    end

    vim.api.nvim_buf_set_lines(buf, first - 1, last, false, {})
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

-- From visual mode the marker goes above the selection, so it reads as a comment
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
