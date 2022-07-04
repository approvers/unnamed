local unnamed = require("unnamed")

local config = {
    workdir = vim.env.HOME .. "/.config/nvim/unnamed",
    repos = {
        {
            repo = "nvim-lualine/lualine.nvim",
            setup = function()
                require("lualine").setup({ theme = "solarized_dark" })
            end,
        },
        {
            repo = "kdheepak/tabline.nvim",
            setup = function()
                require("tabline").setup({ enable = true })
            end,
        },

        -- ### tree-sitter ###
        "windwp/nvim-ts-autotag",
        "nvim-treesitter/playground",
        {
            repo = "nvim-treesitter/nvim-treesitter",
            setup = function()
                require("nvim-treesitter.configs").setup({
                    autotag = { enable = true },
                    playground = { enable = true },
                })
            end,
        },
    },
}

unnamed.setup(config)
