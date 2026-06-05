vim.pack.add { 'https://github.com/uga-rosa/translate.nvim' }

require('translate').setup {
  default = {
    -- NOTE: the plugin only honours parse_before/command/parse_after/output in `default`.
    -- `source`/`target` here are NOT read by the plugin (they only come from the `:Translate`
    -- command line), so we don't set them. The endpoint also rejects source="auto".
    output = 'floating',
  },
  preset = {
    output = {
      floating = { border = 'rounded' },
    },
  },
}

-- Fix: buffer the whole stdout stream before parsing the JSON response.
--
-- Upstream `translate.nvim`'s `_translate` feeds every libuv read chunk straight into
-- `parse_after` (which runs `vim.json.decode`). Short translations arrive in a single read
-- and work, but long ones arrive in several reads: an intermediate chunk starts mid-string,
-- so `vim.json.decode` blows up with "Expected value but found invalid token at character 1".
--
-- We can't fix this via config (the read loop is hardcoded), and patching the plugin file
-- itself would be wiped by `vim.pack.update()`. So we override `_translate` here, mirroring
-- the original but accumulating chunks and decoding once at EOF (`data == nil`).
do
  local translate = require 'translate'
  local config = require 'translate.config'
  local util = require 'translate.util.util'
  local replace = require 'translate.util.replace'
  local luv = vim.uv or vim.loop

  local function pipes()
    return { luv.new_pipe(false), luv.new_pipe(false), luv.new_pipe(false) }
  end

  local function set_to_top(tbl, elem)
    if tbl[1] ~= elem then
      table.insert(tbl, 1, elem)
    end
  end

  function translate._translate(pos, cmd_args)
    local parse_before = config.get_funcs('parse_before', cmd_args.parse_before)
    local command, command_name = config.get_func('command', cmd_args.command)
    local parse_after = config.get_funcs('parse_after', cmd_args.parse_after)
    local output = config.get_func('output', cmd_args.output)

    replace.set_command_name(command_name)
    set_to_top(parse_before, replace.before)
    set_to_top(parse_after, replace.after)

    local after_process = config._preset.parse_after[command_name]
    if after_process and after_process.cmd then
      set_to_top(parse_after, after_process.cmd)
    end

    local lines = translate._selection(pos)
    pos._lines_selected = lines

    lines = translate._run(parse_before, lines, pos, cmd_args)
    if not pos._group then
      pos._group = util.seq(#lines)
    end

    local cmd, args = command(lines, cmd_args)
    local stdio = pipes()

    local handle
    handle = luv.spawn(cmd, { args = args, stdio = stdio }, function(code)
      if not config.get 'silent' then
        print(code == 0 and 'Translate success' or 'Translate failed')
      end
      handle:close()
    end)

    if not handle then
      return
    end

    -- Accumulate every chunk; only parse once the stream is fully read (EOF -> data == nil).
    local chunks = {}
    luv.read_start(
      stdio[2],
      vim.schedule_wrap(function(err, data)
        assert(not err, err)
        if data then
          chunks[#chunks + 1] = data
          return
        end
        local result = table.concat(chunks)
        if result ~= '' then
          result = translate._run(parse_after, result, pos)
          output(result, pos)
        end
      end)
    )
  end
end

-- Normal mode: traduce la palabra bajo el cursor (<leader>tt para no chocar con el grupo Toggle)
vim.keymap.set('n', '<leader>tt', function()
  local word = vim.fn.expand '<cword>'
  local target = word:match '[áéíóúñÁÉÍÓÚÑ¿¡]' and 'en' or 'es'
  -- viw selects the word in visual; `:` auto-prepends `'<,'>` in command line
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('viw:Translate ' .. target .. '<CR>', true, false, true),
    'n', false
  )
end, { desc = '[T]ranslate word' })

-- Visual mode: traduce la selección (<leader>t, libre en visual)
-- Bidireccional: detecta caracteres españoles → traduce a EN; si no → traduce a ES
vim.keymap.set('v', '<leader>t', function()
  local s = vim.fn.getpos "'<"
  local e = vim.fn.getpos "'>"
  local lines = vim.api.nvim_buf_get_text(0, s[2] - 1, s[3] - 1, e[2] - 1, e[3], {})
  local text = table.concat(lines, ' ')
  local target = text:match '[áéíóúñÁÉÍÓÚÑ¿¡]' and 'en' or 'es'
  vim.cmd("'<,'>Translate " .. target)
end, { desc = '[T]ranslate' })
