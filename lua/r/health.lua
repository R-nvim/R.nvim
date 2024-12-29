--- Adapted from markview.nvim plugin

local M = {}

local ts_available, treesitter_parsers = pcall(require, "nvim-treesitter.parsers")

--- Checks if a parser is available or not
---@param parser_name string
---@return boolean
local function parser_installed(parser_name)
    return (ts_available and treesitter_parsers.has_parser(parser_name))
        or pcall(vim.treesitter.query.get, parser_name, "highlights")
end

M.check = function()
    vim.health.start("Checking applications and plugins:")

    if vim.fn.has("nvim-0.9.5") == 1 then
        vim.health.ok("Neovim version: " .. tostring(vim.version()))
    else
        vim.health.error(
            "Minimum Neovim version is `0.9.5`, found: " .. tostring(vim.version())
        )
    end

    if vim.fn.executable("gcc") == 1 or vim.fn.executable("clang") == 1 then
        vim.health.ok("C compiler (`gcc` or `clang`) found.")
    else
        vim.health.error("C compiler (`gcc` or `clang`) not found.")
    end

    if vim.fn.exists("*WaitVimComStart") ~= 0 then
        vim.health.error("Please, uninstall Vim-R-plugin before using R.nvim.")
    elseif vim.fn.exists("*RWarningMsg") ~= 0 then
        vim.health.error("Please, uninstall Nvim-R before using R.nvim.")
    end

    if pcall(require, "cmp") then
        if pcall(require, "cmp_r") then
            vim.health.ok("`R-nvim/cmp-r` found.")
        else
            vim.health.warn("`R-nvim/cmp-r` not found. It's required for autocompletion.")
        end
    else
        vim.health.warn(
            "`hrsh7th/nvim-cmp` not found. It's required for autocompletion along with `R-nvim/cmp-r`."
        )
    end

    if ts_available then
        vim.health.ok("`nvim-treesitter/nvim-treesitter` found.")
    else
        vim.health.warn(
            "`nvim-treesitter/nvim-treesitter` not found. Ignore this if you manually installed the parsers."
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
