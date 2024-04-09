local M = {}

-- Get the starting and ending line numbers of the current paragraph.
-- Returns a table with two keys: 'start' and 'end'.
-- The 'start' key contains the line number of the first line of the paragraph.
-- The 'end' key contains the line number of the last line of the paragraph.
-- If the cursor is on the last paragraph, the 'end' key contains the last line
-- number.
---@return number, number
M.get_current = function()
    local start_line = vim.api.nvim_win_get_cursor(0)[1]
    local end_line = start_line

    -- Find the start of the paragraph
    while start_line > 1 do
        local line = vim.fn.trim(vim.fn.getline(start_line - 1))
        if
            line == ""
            or (vim.o.filetype == "rnoweb" and line:find("^<<"))
            or (
                (vim.o.filetype == "rmd" or vim.o.filetype == "quarto")
                and line:find("^```%{")
            )
        then
            break
        end
        start_line = start_line - 1
    end

    -- Find the end of the paragraph
    local last_line = vim.api.nvim_buf_line_count(0)
    while end_line < last_line do
        local line = vim.fn.trim(vim.fn.getline(end_line + 1))
        if
            line == ""
            or (vim.o.filetype == "rnoweb" and line == "@")
            or ((vim.o.filetype == "rmd" or vim.o.filetype == "quarto") and line == "```")
        then
            break
        end
        end_line = end_line + 1
    end

    return start_line - 1, end_line
end

return M
