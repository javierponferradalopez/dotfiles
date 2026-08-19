local M = {}

local DIR = '.ai-review'
local VERSION = 1

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

local root, gitdir, branch, projection
local stamp
local generation = 0

local function read_file(path)
  local fd = vim.uv.fs_open(path, 'r', 438)
  if not fd then return nil end

  local stat = vim.uv.fs_fstat(fd)
  local body = stat and vim.uv.fs_read(fd, stat.size, 0) or nil
  vim.uv.fs_close(fd)

  return body
end

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

local function decode_store(body) return decode(body) or decode(body and (body:gsub(',(%s*[%]}])', '%1'))) end

local function resolve_root()
  local cwd = vim.uv.cwd()
  return vim.fs.root(cwd, '.git') or cwd
end

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

local function archive_path(name)
  local slug = name:gsub('[^%w%-_.]', function(c) return ('%%%02X'):format(c:byte()) end)
  return vim.fs.joinpath(store_dir(), 'branches', slug .. '.json')
end

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

  decoded.version = VERSION
  decoded.protocol = PROTOCOL
  decoded.branch = name or decoded.branch
  decoded.comments = decoded.comments or {}

  return decoded
end

local function exists() return vim.uv.fs_stat(store_dir()) ~= nil end

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

local function read_branch()
  if not gitdir then return nil end

  local head = read_file(vim.fs.joinpath(gitdir, 'HEAD'))
  local ref = head and head:match 'ref:%s*refs/heads/([^\n]+)'

  return ref and vim.trim(ref) or nil
end

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

local vanished = 0

local function reload()
  local before = #projection.comments
  local decoded = decode_store(read_file(projection_path()))

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

local CHECK_EVERY = 100 * 1e6
local checked = 0

local function ensure_loaded(force)
  if not projection then
    root = resolve_root()
    gitdir = resolve_gitdir(root)

    local state = decode(read_file(state_path())) or {}
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

local function archives()
  local dir = vim.fs.joinpath(store_dir(), 'branches')
  local found = {}
  if not vim.uv.fs_stat(dir) then return found end

  for name, type in vim.fs.dir(dir) do
    if type == 'file' and name:match '%.json$' then table.insert(found, vim.fs.joinpath(dir, name)) end
  end

  return found
end

function M.root()
  ensure_loaded()
  return root
end

function M.branch()
  ensure_loaded()
  return branch
end

function M.generation()
  ensure_loaded()
  return generation
end

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

function M.touch(changed)
  ensure_loaded()
  if changed then generation = generation + 1 end
  save()
end

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

function M.total()
  ensure_loaded()

  local count = #projection.comments

  for _, path in ipairs(archives()) do
    count = count + #read_projection(path, nil).comments
  end

  return count
end

function M.clear_everywhere()
  local removed = M.clear(nil)

  for _, path in ipairs(archives()) do
    removed = removed + #read_projection(path, nil).comments
    vim.uv.fs_unlink(path)
  end

  return removed
end

function M.refresh()
  ensure_loaded(true)

  local gone = vanished
  vanished = 0

  return gone
end

return M
