local assert = require("luassert")
local test_utils = require("tests.test_utils")

describe("Chunk motion", function()
    it("Move the cursor to the next_chunk", function()
        local bufnr = test_utils.create_r_buffer_from_file("tests/fixtures/chunks.qmd")

        -- Set the created buffer as the current buffer
        vim.api.nvim_set_current_buf(bufnr)

        vim.api.nvim_win_set_cursor(0, { 6, 1 })

        -- Move to the next chunk
        require("r.rmd").next_chunk()

        local cursor = vim.api.nvim_win_get_cursor(0)
        assert.same({ 20, 0 }, cursor, "Cursor did not move to the next chunk")
    end)
end)
