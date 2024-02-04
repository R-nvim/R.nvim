local M = {}

-- Returns the line number of the first non-empty line after the current
-- paragraph. If the cursor is on the last paragraph, returns the last line
-- number.
M.find_next_paragraph = function()
    local current_line = vim.fn.line(".")
    local next_empty_line = current_line

    -- Search for the next empty line (paragraph separator)
    while next_empty_line <= vim.fn.line("$") do
        if vim.fn.trim(vim.fn.getline(next_empty_line)) == "" then break end
        next_empty_line = next_empty_line + 1
    end

    -- Move cursor to the first non-empty line after the empty line
    while next_empty_line <= vim.fn.line("$") do
        if vim.fn.trim(vim.fn.getline(next_empty_line)) ~= "" then
            return next_empty_line
        end
        next_empty_line = next_empty_line + 1
    end

    return vim.fn.line("$")
end

-- Moves the cursor to the first non-empty line after the current paragraph.
M.move_next_paragraph = function()
    vim.api.nvim_win_set_cursor(0, { M.find_next_paragraph(), 0 })
end

-- Moe the cursor to the next line
M.move_next_line = function()
    if vim.fn.line(".") == vim.fn.line("$") then return end

    vim.api.nvim_win_set_cursor(0, { vim.fn.line(".") + 1, 0 })
end

return M
