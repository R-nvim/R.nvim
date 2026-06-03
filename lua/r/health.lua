--- Adapted from markview.nvim plugin

local M = {}

M.check = function()
    vim.health.start("Checking applications and plugins:")

    if vim.fn.has("nvim-0.11.4") == 1 then
        vim.health.ok("Neovim version: " .. tostring(vim.version()))
    else
        vim.health.error(
            "Minimum Neovim version is `0.11.4`, found: " .. tostring(vim.version())
        )
    end

    if vim.fn.executable("gcc") == 1 or vim.fn.executable("clang") == 1 then
        vim.health.ok("C compiler (`gcc` or `clang`) found.")
    else
        vim.health.error("C compiler (`gcc` or `clang`) not found.")
    end

    if vim.fn.executable("tree-sitter") == 1 then
        vim.health.ok("Tree-sitter command line application (`tree-sitter`) found.")
    else
        vim.health.ok("Tree-sitter command line application (`tree-sitter`) not found.")
    end

    if vim.fn.exists("*RWarningMsg") ~= 0 then
        vim.health.error("Please, uninstall Vim-R before using R.nvim.")
    elseif vim.fn.exists("*WaitVimComStart") ~= 0 then
        vim.health.error("Please, uninstall Vim-R-plugin before using R.nvim.")
    end

    if vim.fn.executable("yaml-language-server") == 1 then
        vim.health.ok("`yaml-language-server` found.")
    else
        vim.health.warn(
            "`yaml-language-server` not found. You can ignore this if you do not want YAML completion in Quarto files."
        )
    end

    vim.health.start("Checking tree-sitter parser for R:")

    if vim.treesitter.language.add("r") == true then
        vim.health.ok("`r` found.")
    else
        vim.health.error("`r` not found.")
    end

    vim.health.start("Checking other tree-sitter parsers:")

    if vim.treesitter.language.add("csv") == true then
        vim.health.ok("`csv` found.")
    else
        vim.health.warn("`csv` not found (required to view matrices and data frames).")
    end

    if vim.treesitter.language.add("yaml") == true then
        vim.health.ok("`yaml` found.")
    else
        vim.health.warn(
            "`yaml` not found (required to edit RMarkdown, Quarto, Rnoweb and RTypst documents)."
        )
    end

    if vim.treesitter.language.add("rnoweb") == true then
        vim.health.ok("`rnoweb` found.")
    else
        vim.health.warn("`rnoweb` not found (required to edit Rnoweb documents).")
    end

    if vim.treesitter.language.add("typst") == true then
        vim.health.ok("`typst` found.")
    else
        vim.health.warn("`typst` not found (required to edit RTypst documents).")
    end
end

return M
