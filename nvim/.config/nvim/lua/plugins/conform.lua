local lsp_util = require("lspconfig.util")

local function biome_or_prettierd(bufnr)
  local root_dir = lsp_util.root_pattern("biome.json")(vim.api.nvim_buf_get_name(bufnr))

  if root_dir then
    return { "biome" }
  else
    return { "prettierd" }
  end
end

return {
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    opts = function()
      ---@type conform.setupOpts
      local opts = {
        formatters = {
          biome = {
            require_cwd = true,
          },
        },
        formatters_by_ft = {
          css = { "prettierd" },
          html = { "prettierd" },
          javascript = biome_or_prettierd,
          javascriptreact = biome_or_prettierd,
          json = biome_or_prettierd,
          markdown = { "prettierd" },
          typescript = biome_or_prettierd,
          typescriptreact = biome_or_prettierd,
          yaml = { "prettierd" },
        }
      }
      return opts
    end,
  },
}
