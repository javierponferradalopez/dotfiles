-- On-disk home for the review comments: where they live, how they are read and
-- written, and which of them belong to the branch you are on right now.
--
--   comments.json         the comments of the *active* branch. Shared: you write
--                         them here, and the agent deletes the ones it has done.
--   branches/<name>.json  the same, for the branches you are not on. Neovim only.
--   state.json            which branch comments.json currently belongs to.
--
-- The agent closing a comment IS deleting it, so there is nothing for it to say
-- back and no second file to say it in. What that costs is the one-writer rule:
-- this module has to assume the file changed under it, which it does by comparing
-- what is on disk with what it last left there and reloading when they differ.
-- Hence one comment per line in the encoder -- closing one is a one-line edit,
-- not a rewrite -- and hence the reload before anything is written.
--
-- Nothing outside this module knows that any of it is JSON on a disk.

local M = {}

local DIR = '.ai-review'
local VERSION = 1

-- What the agent is told when it opens the projection. It travels with the data
-- instead of living in CLAUDE.md for two reasons: the contract cannot drift from
-- the code that produces it, and the global instructions stay two lines long
-- however much this format grows.
local PROTOCOL = {
  'Review comments written by the human, addressed to you (the agent).',
  'Each one is about the code at path:line (through end_line when present).',
  'The human keeps writing here while you work, so what you have read is a copy and',
  'it goes stale: read this file again before you act on a comment.',
  'When you have done what a comment asks, delete it: one comment is one line of',
  'the "comments" array, so it is a one-line edit. Keep the JSON valid -- the last',
  'entry carries no trailing comma.',
  'Deleting it is the whole of closing it. Nothing of it is kept, so what you did,',
  'what you would not do, and what you did not follow go in our conversation, not',
  'in this file. Change nothing else in it.',
  'A comment you have not done stays exactly where it is: one still here is one',
  'still open between us.',
  'If a comment has "orphaned": true its line is NOT reliable: locate the code by',
  'its "snippet" and confirm before touching anything. If you cannot find it, do',
  'not guess -- ask.',
}

-- Everything below is memoised for the session: root and gitdir do not move, and
-- the projection is the in-memory truth that gets flushed on every change.
local root, gitdir, branch, projection
-- What comments.json looked like when we last wrote it. Anything else on disk is
-- the agent's doing, and the agent's copy wins.
local stamp
local generation = 0

---------------------------------------------------------------------- plumbing

local function read_file(path)
  local fd = vim.uv.fs_open(path, 'r', 438)
  if not fd then return nil end

  local stat = vim.uv.fs_fstat(fd)
  local body = stat and vim.uv.fs_read(fd, stat.size, 0) or nil
  vim.uv.fs_close(fd)

  return body
end

-- Write via a temporary file and a rename, never by truncating in place: a crash
-- halfway through must not leave a half-parsed JSON behind, because since the
-- comments left the code this file is the only record of them.
local function write_file(path, body)
  local tmp = path .. '.tmp'
  local fd = vim.uv.fs_open(tmp, 'w', 420)
  if not fd then
    vim.notify('ai-review: cannot write ' .. path, vim.log.levels.ERROR)
    return false
  end

  vim.uv.fs_write(fd, body, 0)
  vim.uv.fs_close(fd)
  vim.uv.fs_rename(tmp, path)

  return true
end

local function decode(body)
  if not body or vim.trim(body) == '' then return nil end

  local ok, value = pcall(vim.json.decode, body, { luanil = { object = true, array = true } })
  if ok and type(value) == 'table' then return value end

  return nil
end

-- The store as the agent may have left it. Deleting the last comment of the array
-- leaves the comma before it dangling, which is invalid JSON and is also not a
-- corrupt store -- it is a one-character slip in an edit we asked for. Repaired on
-- the way in, and gone for good on the next write, which reformats anyway. Only
-- ever tried on a body that already failed to parse, so it cannot make a readable
-- store worse.
local function decode_store(body)
  return decode(body) or decode(body and (body:gsub(',(%s*[%]}])', '%1')))
end

------------------------------------------------------------------------- paths

-- The project root is the directory holding `.git` -- a directory in a normal
-- clone, a file pointing elsewhere in a worktree. Outside git we fall back to
-- the cwd so the tool still works, just without branch awareness.
local function resolve_root()
  local cwd = vim.uv.cwd()
  return vim.fs.root(cwd, '.git') or cwd
end

-- Where git keeps HEAD for this checkout. In a worktree `.git` is a file holding
-- `gitdir: <path>`, which may be relative to the root.
local function resolve_gitdir(project)
  local dot = vim.fs.joinpath(project, '.git')
  local stat = vim.uv.fs_stat(dot)
  if not stat then return nil end
  if stat.type == 'directory' then return dot end

  local pointer = (read_file(dot) or ''):match 'gitdir:%s*([^\n]+)'
  if not pointer then return nil end

  pointer = vim.trim(pointer)
  if not vim.startswith(pointer, '/') then pointer = vim.fs.joinpath(project, pointer) end

  return vim.fs.normalize(pointer)
end

local function store_dir() return vim.fs.joinpath(root, DIR) end
local function projection_path() return vim.fs.joinpath(store_dir(), 'comments.json') end
local function state_path() return vim.fs.joinpath(store_dir(), 'state.json') end

-- Branch names carry slashes and other things a filename should not, so escape
-- anything that is not plainly safe. Percent-escaping keeps it reversible, which
-- matters only for eyeballing the directory: the branch is also stored inside
-- each file, and that is what the code reads back.
local function archive_path(name)
  local slug = name:gsub('[^%w%-_.]', function(c) return ('%%%02X'):format(c:byte()) end)
  return vim.fs.joinpath(store_dir(), 'branches', slug .. '.json')
end

-- Keep the store out of git without touching a shared .gitignore: these comments
-- are personal and throwaway, and adding noise to a file the whole team reads is
-- not this tool's business.
local function ensure_excluded()
  if not gitdir then return end

  local path = vim.fs.joinpath(gitdir, 'info', 'exclude')
  local body = read_file(path) or ''
  local entry = '/' .. DIR .. '/'
  if body:find(entry, 1, true) then return end

  local separator = (body ~= '' and not vim.endswith(body, '\n')) and '\n' or ''
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  write_file(path, body .. separator .. entry .. '\n')
end

-------------------------------------------------------------------- projection

-- Hand-rolled layout rather than a bare `vim.json.encode` of the whole table:
-- this file is read by a human and by an agent, so the protocol has to be
-- legible and each comment has to sit on its own line instead of in one endless
-- one. The values still go through vim.json.encode, so the escaping is not ours
-- to get wrong.
local function encode(p)
  local out = { '{' }

  table.insert(out, '  "version": ' .. tostring(p.version) .. ',')
  table.insert(out, '  "branch": ' .. (p.branch and vim.json.encode(p.branch) or 'null') .. ',')

  table.insert(out, '  "protocol": [')
  for i, text in ipairs(p.protocol) do
    table.insert(out, '    ' .. vim.json.encode(text) .. (i < #p.protocol and ',' or ''))
  end
  table.insert(out, '  ],')

  if #p.comments == 0 then
    table.insert(out, '  "comments": []')
  else
    table.insert(out, '  "comments": [')
    for i, comment in ipairs(p.comments) do
      table.insert(out, '    ' .. vim.json.encode(comment) .. (i < #p.comments and ',' or ''))
    end
    table.insert(out, '  ]')
  end

  table.insert(out, '}')

  return table.concat(out, '\n') .. '\n'
end

local function empty(name) return { version = VERSION, branch = name, protocol = PROTOCOL, comments = {} } end

-- Read a projection, keeping a corrupt one rather than overwriting it: it holds
-- comments that exist nowhere else, so the user gets the chance to salvage them.
local function read_projection(path, name)
  local body = read_file(path)
  if not body then return empty(name) end

  local decoded = decode_store(body)
  if not decoded then
    local kept = path .. '.corrupt'
    vim.uv.fs_rename(path, kept)
    vim.notify('ai-review: unreadable store, kept a copy at ' .. kept, vim.log.levels.ERROR)
    return empty(name)
  end

  -- The version and the protocol always come from the code, never from the file:
  -- the contract the agent reads is whatever this plugin currently understands.
  decoded.version = VERSION
  decoded.protocol = PROTOCOL
  -- Only the caller that knows which branch it is asking for gets to set it. The
  -- ones that read an archive blind (applying a reply, pruning) pass no name, and
  -- must not erase the one the file already carries -- it is how a store is tied
  -- back to its branch once the filename has been escaped.
  decoded.branch = name or decoded.branch
  decoded.comments = decoded.comments or {}

  return decoded
end

-- The store comes into existence with your first comment, never merely because a
-- buffer was opened: the branch check runs on every BufEnter, so without this a
-- project you only visited would end up with a directory and an exclude entry it
-- never asked for. Once it does exist we keep it up to date even when it empties
-- out, since the active branch still matters.
local function exists() return vim.uv.fs_stat(store_dir()) ~= nil end

-- Enough of the file to tell our own writing from someone else's. Size alone would
-- miss an edit that happens to keep the length; the nanosecond mtime alone would
-- miss nothing in practice, but the two together cost one stat either way.
local function fingerprint()
  local stat = vim.uv.fs_stat(projection_path())
  if not stat then return nil end

  return ('%d.%d:%d'):format(stat.mtime.sec, stat.mtime.nsec, stat.size)
end

local function save()
  if #projection.comments == 0 and not exists() then return end

  vim.fn.mkdir(store_dir(), 'p')
  ensure_excluded()
  write_file(projection_path(), encode(projection))
  stamp = fingerprint()
  write_file(state_path(), vim.json.encode { branch = branch } .. '\n')
end

------------------------------------------------------------------------ branch

-- Read the branch straight out of `.git/HEAD` instead of forking git: this runs
-- on every BufEnter. `nil` means a detached HEAD -- a rebase, a bisect, a
-- checked-out commit -- and callers deliberately stay on the current store in
-- that case, so a rebase does not make your comments blink out and back.
local function read_branch()
  if not gitdir then return nil end

  local head = read_file(vim.fs.joinpath(gitdir, 'HEAD'))
  local ref = head and head:match 'ref:%s*refs/heads/([^\n]+)'

  return ref and vim.trim(ref) or nil
end

-- Park the branch we are leaving and bring in the one we arrived at, keeping one
-- invariant: a branch's comments live in comments.json while it is active and in
-- branches/<name>.json while it is not. Never in both.
local function switch_to(target)
  if branch then
    local parked = archive_path(branch)
    vim.fn.mkdir(vim.fs.dirname(parked), 'p')
    write_file(parked, encode(projection))
  end

  local archived = archive_path(target)
  projection = read_projection(archived, target)
  branch = target
  vim.uv.fs_unlink(archived)

  generation = generation + 1
  save()
end

-- How many comments the last reload found missing, waiting for someone to be told.
-- It is kept here rather than returned because the reload happens deep inside a
-- load check that most callers neither ask for nor care about, and the one caller
-- that does care asks later.
local vanished = 0

-- Take the file back as the truth, because someone else wrote it. Nothing is
-- merged: an edit we did not make wins whole, and reconciling two versions of the
-- list would be a lot of machinery to decide something the agent already decided.
local function reload()
  local before = #projection.comments
  local decoded = decode_store(read_file(projection_path()))

  -- Unreadable is not a reason to throw away the comments we are holding: ours are
  -- as good as whatever is down there, and the next write puts the file right.
  if not decoded then
    vim.notify('ai-review: the store changed and cannot be read, keeping the comments in memory', vim.log.levels.ERROR)
    stamp = fingerprint()
    return
  end

  decoded.version = VERSION
  decoded.protocol = PROTOCOL
  decoded.branch = branch
  decoded.comments = decoded.comments or {}

  projection = decoded
  stamp = fingerprint()
  generation = generation + 1
  vanished = vanished + math.max(before - #projection.comments, 0)
end

-- Looking for the branch and for someone else's edit both hit the disk, and the
-- gutter asks this module for a comment on every line it draws. So the checks are
-- rate-limited: a tenth of a second is far below what you could notice and far
-- above a redraw. `force` is for the moments we know something may have changed --
-- entering a buffer, coming back to the window -- where waiting is not on.
local CHECK_EVERY = 100 * 1e6
local checked = 0

local function ensure_loaded(force)
  if not projection then
    root = resolve_root()
    gitdir = resolve_gitdir(root)

    local state = decode(read_file(state_path())) or {}
    -- Whose comments comments.json currently holds -- not necessarily the branch
    -- we are on, since the last session may have ended somewhere else.
    branch = state.branch
    projection = read_projection(projection_path(), branch)
    stamp = fingerprint()
  else
    local now = vim.uv.hrtime()
    if not force and now - checked < CHECK_EVERY then return end
    checked = now

    if exists() and fingerprint() ~= stamp then reload() end
  end

  local current = read_branch()
  if current and current ~= branch then switch_to(current) end
end

----------------------------------------------------------------------- branches

local function archives()
  local dir = vim.fs.joinpath(store_dir(), 'branches')
  local found = {}
  if not vim.uv.fs_stat(dir) then return found end

  for name, type in vim.fs.dir(dir) do
    if type == 'file' and name:match '%.json$' then table.insert(found, vim.fs.joinpath(dir, name)) end
  end

  return found
end

--------------------------------------------------------------------- public API

function M.root()
  ensure_loaded()
  return root
end

function M.branch()
  ensure_loaded()
  return branch
end

-- Bumped on every change, so the buffer side can tell whether the marks it
-- placed are still current without diffing anything.
function M.generation()
  ensure_loaded()
  return generation
end

-- Path as stored: relative to the project root, so the store survives being
-- cloned somewhere else. `nil` for anything outside the project.
function M.relpath(abs)
  if not abs or abs == '' then return nil end
  ensure_loaded()

  local normalised = vim.fs.normalize(vim.fn.fnamemodify(abs, ':p'))
  local prefix = vim.fs.normalize(root) .. '/'
  if not vim.startswith(normalised, prefix) then return nil end

  return normalised:sub(#prefix + 1)
end

function M.abspath(rel)
  ensure_loaded()
  return vim.fs.joinpath(root, rel)
end

function M.comments()
  ensure_loaded()
  return projection.comments
end

function M.for_path(rel)
  local found = {}

  for _, comment in ipairs(M.comments()) do
    if comment.path == rel then table.insert(found, comment) end
  end

  return found
end

function M.get(id)
  for _, comment in ipairs(M.comments()) do
    if comment.id == id then return comment end
  end
end

-- One comment per anchor line, so `<leader>aa` never has to ask which one you
-- meant and rendering never has to stack them.
function M.at(rel, line)
  for _, comment in ipairs(M.comments()) do
    if comment.path == rel and comment.line == line then return comment end
  end
end

function M.add(entry)
  ensure_loaded()

  entry.id = ('%s-%06x'):format(os.date '!%Y%m%dT%H%M%S', vim.uv.hrtime() % 0x1000000)
  entry.created_at = os.date '!%Y-%m-%dT%H:%M:%SZ'
  table.insert(projection.comments, entry)

  generation = generation + 1
  save()

  return entry
end

function M.remove(id)
  ensure_loaded()

  for i, comment in ipairs(projection.comments) do
    if comment.id == id then
      table.remove(projection.comments, i)
      generation = generation + 1
      save()
      return true
    end
  end

  return false
end

-- For everything that edits a comment in place (its text, or the line an extmark
-- says it drifted to): the caller mutated the table, we just persist it.
function M.touch(changed)
  ensure_loaded()
  if changed then generation = generation + 1 end
  save()
end

-- Drop the comments of one file, or of the whole branch. Returns how many went.
function M.clear(rel)
  ensure_loaded()

  local kept, removed = {}, 0

  for _, comment in ipairs(projection.comments) do
    if rel and comment.path ~= rel then
      table.insert(kept, comment)
    else
      removed = removed + 1
    end
  end

  if removed > 0 then
    projection.comments = kept
    generation = generation + 1
    save()
  end

  return removed
end

-- Everything in the store, the comments parked on the branches you are not on
-- included. There is one caller and it is a prompt: a wipe this wide should be
-- able to say how much is about to go.
function M.total()
  ensure_loaded()

  local count = #projection.comments

  for _, path in ipairs(archives()) do
    count = count + #read_projection(path, nil).comments
  end

  return count
end

-- The wipe that reaches the other branches, which nothing else here does: their
-- comments are parked in files you never open, so without this the only way to be
-- rid of them is to go and stand on each branch in turn. Returns how many went.
function M.clear_everywhere()
  local removed = M.clear(nil)

  for _, path in ipairs(archives()) do
    removed = removed + #read_projection(path, nil).comments
    vim.uv.fs_unlink(path)
  end

  return removed
end

-- Catch up with the file, now rather than within the next tenth of a second, and
-- answer the one question that a deletion you did not make leaves behind: how many
-- comments the agent took while you were looking elsewhere.
function M.refresh()
  ensure_loaded(true)

  local gone = vanished
  vanished = 0

  return gone
end

return M
