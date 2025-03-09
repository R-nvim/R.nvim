local assert = require("luassert")

describe("Chunk motion", function()
    it("Move the cursor to the next_chunk", function()
        local r_code = [[
            ```{r}
            x <- 1:10
            ````
            ```{r}
            y <- x^2
            ````
        ]]

        -- Trim spaces from lines
        local trimmed_lines = {}
        for line in r_code:gmatch("[^\n]+") do
            table.insert(trimmed_lines, line:match("^%s*(.-)%s*$"))
        end

        -- Create buffer, set lines, and configure filetype
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, trimmed_lines)
        vim.api.nvim_buf_set_option(bufnr, "filetype", "quarto")

        -- Set the created buffer as the current buffer
        vim.api.nvim_set_current_buf(bufnr)

        -- Set cursor to the first line
        vim.api.nvim_win_set_cursor(0, { 1, 1 })

        -- Move to the next chunk
        require("r.rmd").next_chunk()

        local cursor = vim.api.nvim_win_get_cursor(0)
        assert.same({ 5, 0 }, cursor, "Cursor did not move to the next chunk")
    end)
end)
