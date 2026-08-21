local M = {}

-- Directories that never hold the tests we're after, but do hold thousands of
-- files each: skipping them keeps the lookup instant on big repos.
local EXCLUDES = { 'node_modules', '.git', 'dist', 'build', '.next', 'vendor', 'target', 'coverage' }

-- Glob patterns for a test file covering `%s`, the stem of the source file.
-- Tests are found by convention, not through the LSP: the same source file is
-- covered by `Foo.test.ts`, `foo_test.go`, `test_foo.py` or `FooTest.php`
-- depending on the language, and no server exposes that relation.
local TEST_PATTERNS = {
  '%s.test.*',
  '%s.spec.*',
  '%s_test.*',
  '%s_spec.*',
  'test_%s.*',
  '%sTest.*',
  '%sTests.*',
  '%sSpec.*',
  '__tests__/%s.*',
  'test/%s.*',
  'tests/%s.*',
  'spec/%s.*',
}

-- Test markers that are unambiguous enough to strip: from `Foo.test.ts` we want
-- the *other* tests of `Foo`, not the tests of a file named `Foo.test`. The
-- PascalCase `FooTest` convention is deliberately left alone -- stripping it
-- would also mangle ordinary names ending in "Test", like `Latest`.
local TEST_MARKERS = { '%.test$', '%.spec$', '_test$', '_spec$' }

--- Stem of the source file a test file belongs to (or the stem itself when the
--- buffer is not a test file).
---@param stem string filename without its extension
---@return string
local function source_stem(stem)
  for _, marker in ipairs(TEST_MARKERS) do
    local stripped = stem:gsub(marker, '')
    if stripped ~= stem then return stripped end
  end
  return (stem:gsub('^test_', ''))
end

local function repo_root()
  local root = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')[1]
  return (root and root ~= '') and root or vim.fn.getcwd()
end

--- Command listing every file matching any of `globs`, relative to its cwd.
---@param globs string[]
---@return string[]
local function build_cmd(globs)
  if vim.fn.executable 'rg' == 1 then
    local cmd = { 'rg', '--files', '--hidden' }
    for _, ex in ipairs(EXCLUDES) do
      vim.list_extend(cmd, { '--glob', '!' .. ex })
    end
    for _, glob in ipairs(globs) do
      vim.list_extend(cmd, { '--glob', '**/' .. glob })
    end
    return cmd
  end

  local cmd = { 'find', '.', '-type', 'f', '(' }
  for i, glob in ipairs(globs) do
    if i > 1 then table.insert(cmd, '-o') end
    -- `-path` matches the whole path, so the leading `*/` is what makes these
    -- globs behave like rg's `**/`.
    vim.list_extend(cmd, { '-path', '*/' .. glob })
  end
  table.insert(cmd, ')')
  for _, ex in ipairs(EXCLUDES) do
    vim.list_extend(cmd, { '-not', '-path', '*/' .. ex .. '/*' })
  end
  return cmd
end

--- Test files for `stem` found under `root`, nearest ones first and never the
--- buffer we started from.
---@param root string directory to search in
---@param stem string source stem the tests are named after
---@param current string absolute path of the current file
---@return string[] absolute paths
local function find_tests(root, stem, current)
  local globs = {}
  for _, pattern in ipairs(TEST_PATTERNS) do
    table.insert(globs, pattern:format(stem))
  end

  local out = vim.system(build_cmd(globs), { cwd = root, text = true }):wait()
  local seen, results = {}, {}
  for path in (out.stdout or ''):gmatch '[^\n]+' do
    local abs = vim.fs.normalize(root .. '/' .. (path:gsub('^%./', '')))
    if abs ~= current and not seen[abs] then
      seen[abs] = true
      table.insert(results, abs)
    end
  end

  -- A test sitting next to its source is the likeliest target, so it wins over
  -- one buried in a mirrored `tests/` tree elsewhere.
  local dir = vim.fs.dirname(current)
  table.sort(results, function(a, b)
    local a_near, b_near = vim.fs.dirname(a) == dir, vim.fs.dirname(b) == dir
    if a_near ~= b_near then return a_near end
    return a < b
  end)
  return results
end

---@param results string[] absolute paths
---@param stem string source stem, for the prompt title
local function pick(results, stem)
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values

  pickers
    .new({}, {
      prompt_title = 'Tests for ' .. stem .. ' (' .. #results .. ')',
      finder = finders.new_table {
        results = results,
        entry_maker = function(path)
          local rel = vim.fn.fnamemodify(path, ':~:.')
          return { value = path, path = path, filename = path, display = rel, ordinal = rel }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = conf.file_previewer {},
    })
    :find()
end

--- Jump to the test files covering the current buffer: straight to the file
--- when there is only one, through a picker when there are several.
function M.goto_tests()
  local current = vim.api.nvim_buf_get_name(0)
  if current == '' then
    vim.notify('No file in this buffer', vim.log.levels.WARN)
    return
  end
  current = vim.fs.normalize(current)

  local stem = source_stem(vim.fn.fnamemodify(current, ':t:r'))
  local cwd = vim.fn.getcwd()
  local results = find_tests(cwd, stem, current)

  -- With a sub-project focused, the cwd is that sub-project: widen to the whole
  -- repo before giving up, so a focused scope never hides a test that exists.
  local root = repo_root()
  if #results == 0 and root ~= cwd then results = find_tests(root, stem, current) end

  if #results == 0 then
    vim.notify('No test files found for ' .. stem, vim.log.levels.WARN)
  elseif #results == 1 then
    vim.cmd.edit(vim.fn.fnameescape(results[1]))
  else
    pick(results, stem)
  end
end

return M
