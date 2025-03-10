return {
  "nvim-telescope/telescope.nvim",
  keys = {
    -- disable the keymap
    { "<leader>sG", false },
    { "<leader>sg", false },
    { "<leader>fF", false },
    { "<leader>fg", false },
    { "<leader>ff", false },
    { "<leader><space>", false },

    -- change keymaps
    -- CWR
    { "<leader>sw", "<cmd>Telescope live_grep<cr>", desc = "Find with Grep" },
    { "<leader>sf", "<cmd>Telescope find_files<cr>", desc = "Find files" },

    -- ROOT DIR
    { "<leader>sF", "<cmd>Telescope git_files<cr>", desc = "Find files (Workspace)" },

    -- Show projects
    { "<leader>fp", "<cmd>Telescope projects<cr>", desc = "Show projects" },
  },
}
