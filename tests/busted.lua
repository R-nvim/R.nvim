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
        {
            [1] = "nvim-treesitter/nvim-treesitter",
            config = function()
                require("nvim-treesitter.configs").setup({
                    sync_install = true,
                    ensure_installed = { "latex", "r", "rnoweb", "yaml" },
                })
            end,
        },
    },
})

-- Ensure the R parser is installed before running tests
local parser_path = vim.fn.globpath(vim.o.runtimepath, "parser/r.so")
if parser_path == "" then vim.cmd("TSInstallSync r --quiet --yes") end

-- Verify the installation
parser_path = vim.fn.globpath(vim.o.runtimepath, "parser/r.so")
if parser_path == "" then
    error("Tree-sitter R parser is missing! Check the installation.")
end
