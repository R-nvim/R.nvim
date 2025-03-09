#!/usr/bin/env -S nvim -l

vim.env.LAZY_STDPATH = ".tests"
load(
    vim.fn.system(
        "curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"
    )
)()

-- Setup lazy.nvim
require("lazy.minit").busted({
    spec = {
        "LazyVim/starter",
        "williamboman/mason-lspconfig.nvim",
        "williamboman/mason.nvim",
        "nvim-treesitter/nvim-treesitter",
    },
})

-- Ensure the R parser is installed before running tests
-- vim.cmd("TSInstallSync r")

-- To use this, you can run:
-- nvim -l ./tests/busted.lua tests
-- If you want to inspect the test environment, run:
-- nvim -u ./tests/busted.lua
