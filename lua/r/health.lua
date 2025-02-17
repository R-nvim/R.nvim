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

--- Create a buffer and check the languages at different cursor positions
---@return table
local check_buffer = function(ft, lines, langs)
    -- Create a temporary buffer in a temporary window
    local b = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_option_value("bufhidden", "wipe", { scope = "local" })
    vim.api.nvim_set_option_value("number", false, { scope = "local" })
    vim.api.nvim_set_option_value("swapfile", false, { scope = "local" })
    vim.api.nvim_set_option_value("buftype", "nofile", { scope = "local" })
    local w = vim.api.nvim_open_win(b, true, {
        relative = "win",
        row = 1,
        col = 1,
        width = 20,
        height = 13,
        hide = true,
    })

    vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    vim.api.nvim_set_option_value("filetype", ft, { buf = b })
    vim.cmd("redraw")

    for k, v in pairs(langs) do
        vim.api.nvim_win_set_cursor(w, { v[2], v[3] })
        langs[k][4] = require("r.utils").get_lang()
    end

    vim.api.nvim_win_close(w, true)
    vim.api.nvim_buf_delete(b, { force = true })

    return langs
end

local print_lang_check = function(langtbl)
    for _, v in pairs(langtbl) do
        if v[1] == v[4] then
            vim.health.ok("Correctly detected: `" .. v[1] .. "`")
        else
            vim.health.error("Wrongly detected: `" .. v[1] .. "` vs `" .. v[4] .. "`")
        end
    end
end

--- Check if language detection using treesitter is working
local check_lang = function()
    -- Quarto document
    local lines = {
        "---",
        "title: Test",
        "---",
        "",
        "Normal text.",
        "",
        "```{r}",
        "x <- 1",
        "```",
        "",
        "Normal text again.",
    }

    -- Expected language at different cursor positions
    local qlangs = {
        { "yaml", 2, 0, "" },
        { "markdown", 4, 0, "" },
        { "markdown_inline", 5, 0, "" },
        { "chunk_header", 7, 0, "" },
        { "r", 8, 0, "" },
        { "chunk_end", 9, 0, "" },
    }

    qlangs = check_buffer("quarto", lines, qlangs)

    -- Rnoweb document
    lines = {
        "\\documentclass{article}",
        "\\begin{document}",
        "",
        "Normal text.",
        "",
        "<<example>>=",
        "x <- 1",
        "@",
        "",
        "Normal text again.",
        "",
        "\\end{document}",
    }

    -- Expected language at different cursor positions
    local nlangs = {
        { "latex", 4, 0, "" },
        { "chunk_header", 6, 0, "" },
        { "r", 7, 0, "" },
        { "chunk_end", 8, 0, "" },
    }

    nlangs = check_buffer("rnoweb", lines, nlangs)

    vim.health.start("Checking language detection in a Quarto document:")
    print_lang_check(qlangs)

    vim.health.start("Checking language detection in an Rnoweb document:")
    print_lang_check(nlangs)
end

M.check = function()
    vim.health.start("Checking applications and plugins:")

    if vim.fn.has("nvim-0.10.4") == 1 then
        vim.health.ok("Neovim version: " .. tostring(vim.version()))
    else
        vim.health.error(
            "Minimum Neovim version is `0.10.4`, found: " .. tostring(vim.version())
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

    check_lang()
end

return M
