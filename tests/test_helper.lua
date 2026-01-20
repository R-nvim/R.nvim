--- Test helper to set up common test environment
--- This should be required at the top of test files or in .busted

local M = {}

--- Setup tree-sitter parsers and registrations
function M.setup_parsers()
    -- Ensure R parser is available
    vim.treesitter.language.add("r")

    -- Register markdown parser for quarto and rmd filetypes
    -- This is needed because quarto files use markdown syntax with embedded code
    pcall(vim.treesitter.language.register, "markdown", { "quarto", "rmd" })
end

--- Call setup automatically when module is loaded
M.setup_parsers()

return M