local M = {}
-- Get the starting and ending line numbers of the current paragraph.
-- Returns a table with two keys: 'start' and 'end'.
-- The 'start' key contains the line number of the first line of the paragraph.
-- The 'end' key contains the line number of the last line of the paragraph.
-- If the cursor is on the last paragraph, the 'end' key contains the last line
-- number.
M.get_current = function()
    local current_line = vim.fn.line(".")
    local start_line = current_line
    local end_line = current_line

    -- Find the start of the paragraph
    while start_line > 1 and vim.fn.trim(vim.fn.getline(start_line - 1)) ~= "" do
        start_line = start_line - 1
    end

    -- Find the end of the paragraph
    local last_line = vim.fn.line("$")
    while end_line < last_line and vim.fn.trim(vim.fn.getline(end_line + 1)) ~= "" do
        end_line = end_line + 1
    end

    return start_line, end_line
end

return M
