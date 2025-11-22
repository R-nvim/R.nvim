--- Adapted from markview.nvim plugin

local M = {}

local ts_available, treesitter_parsers = pcall(require, "nvim-treesitter.parsers")

--- Checks if a parser is available or not
---@param parser_name string
---@return boolean
local function parser_installed(parser_name)
    return (
        ts_available
        and treesitter_parsers.has_parser
        and treesitter_parsers.has_parser(parser_name)
    ) or pcall(vim.treesitter.query.get, parser_name, "highlights")
end

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

    if ts_available then
        vim.health.ok("`nvim-treesitter/nvim-treesitter` found.")
    else
        vim.health.warn(
            "`nvim-treesitter/nvim-treesitter` not found. Ignore this if you manually installed the parsers."
        )
    end

    if vim.fn.executable("yaml-language-server") == 1 then
        vim.health.ok("`yaml-language-server` found.")
    else
        vim.health.warn(
            "`yaml-language-server` not found. You can ignore this if you do not want YAML completion in Quarto files."
        )
    end

    vim.health.start("Checking tree-sitter parsers:")

    for _, parser in ipairs({
        "r",
        "markdown",
        "markdown_inline",
        "rnoweb",
        "latex",
        "yaml",
    }) do
        if parser_installed(parser) then
            vim.health.ok("`" .. parser .. "` " .. " found.")
        else
            vim.health.error("`" .. parser .. "` " .. "not found.")
        end
    end
end

return M
