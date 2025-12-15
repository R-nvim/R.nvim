#!/usr/bin/env -S nvim -l

vim.env.LAZY_STDPATH = ".tests"
load(
    vim.fn.system(
        "curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"
    )
)()

-- Setup lazy.nvim with proper treesitter configuration
require("lazy.minit").busted({
    spec = {
        "LazyVim/starter",
        "williamboman/mason-lspconfig.nvim",
        "williamboman/mason.nvim",
        {
            [1] = "nvim-treesitter/nvim-treesitter",
            branch = "main",
            build = ":TSUpdate",
            lazy = false,
            opts = {
                ensure_installed = {
                    "markdown",
                    "markdown_inline",
                    "r",
                    "rnoweb",
                    "yaml",
                },
            },
            config = function(_, opts)
                -- Configure nvim-treesitter with install directory
                local install_dir = vim.fn.stdpath("data") .. "/site"
                require("nvim-treesitter").setup({
                    install_dir = install_dir,
                })

                -- Install ensure_installed parsers
                if opts.ensure_installed then
                    print("\n=== Installing treesitter parsers ===")
                    require("nvim-treesitter").install(opts.ensure_installed):wait(300000)
                    print("=== Parser installation complete ===")
                end

                -- Verify parser installation
                print("\n=== Verifying parser files ===")
                local config = require("nvim-treesitter.config")
                local parser_dir = config.get_install_dir("parser")
                print(string.format("Parser directory: %s", parser_dir))
                local parser_files = vim.fn.glob(parser_dir .. "/*.so", false, true)
                print(string.format("Found %d .so files:", #parser_files))
                for _, file in ipairs(parser_files) do
                    print(string.format("  - %s", vim.fn.fnamemodify(file, ":t")))
                end
                print("")

                -- Register markdown parser for quarto and rmd filetypes
                vim.treesitter.language.register("markdown", { "quarto", "rmd" })
            end,
        },
    },
})
