local unnamed = require("unnamed")

local config = {
    workdir = vim.env.HOME .. "/.config/nvim/unnamed",
    repos = {
        {
            repo = "nvim-lualine/lualine.nvim",
            fast_setup = function()
                require("lualine").setup({ theme = "solarized_dark" })
            end,
        },
        {
            repo = "kdheepak/tabline.nvim",
            fast_setup = function()
                require("tabline").setup({ enable = true })
            end,
        },

        -- ### tree-sitter ###
        "windwp/nvim-ts-autotag",
        {
            repo = "nvim-treesitter/nvim-treesitter",
            branch = "main",
            setup = function()
                require("nvim-treesitter").setup({})
            end,
        },
    },
}

unnamed.setup(config)
