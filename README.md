# Unnamed

> a simple Neovim plugin manager which aims for fast start-up

- fully written in lua
- supports lazy loading
- organizes all plugins to single directory for faster loading
- uses blob-less clone to reduce disk usage and update faster

To start using unnamed, write these lines to your config!

```lua
local uv = vim.loop

-- install unnamed if required
local unnamed_path = vim.env.HOME .. "/.config/nvim/unnamed"
local stat, err = uv.fs_stat(unnamed_path)
if stat == nil then
    vim.notify("installing unnamed")
    vim.fn.system("git clone https://github.com/approvers/unnamed.git " .. unnamed_path)
end

vim.opt.runtimepath:prepend(unnamed_path)

local plugins = {
    -- if no setup required, you can directly write repo name
    "windwp/nvim-ts-autotag",
    -- use `fast_setup` to run setup function before first screen update
    {
        repo = "ishan9299/nvim-solarized-lua",
        fast_setup = function()
            vim.cmd("colorscheme solarized-flat")
        end,
    },
    -- use `setup` to run setup function lazily
    {
        repo = "folke/trouble.nvim",
        setup = function()
            require("trouble").setup()
        end,
    },
}

require("unnamed").setup({
    workdir = unnamed_path,
    repos = plugins,
})
```

To update your plugins, use this command:

```lua
:lua require("unnamed").update()
```

#### development prerequirements

- just
- stylua
- docker
- pre-commit

#### how to develop

1. run `pre-commit install` only the first time you cloned the repo
1. `just dev`
1. edit files under `lua/`, test it on `just dev`ed shell.
