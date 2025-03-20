local assert = require("luassert")
local test_utils = require("./utils")

describe("Chunk motion functionality", function()
    it(
        "Moves the cursor to the next chunk, skipping chunks with eval set to false",
        function()
            local bufnr =
                test_utils.create_r_buffer_from_file("tests/fixtures/chunks.qmd")

            vim.api.nvim_set_current_buf(bufnr)

            vim.api.nvim_win_set_cursor(0, { 7, 0 })

            require("r.rmd").next_chunk()

            local cursor = vim.api.nvim_win_get_cursor(0)

            assert.same({ 22, 0 }, cursor, "Cursor did not move to the next chunk")
        end
    )
    it(
        "Moves the cursor to the next chunk, even if the cursor is on a chunk header with eval set to false",
        function()
            local bufnr =
                test_utils.create_r_buffer_from_file("tests/fixtures/chunks.qmd")

            vim.api.nvim_set_current_buf(bufnr)

            vim.api.nvim_win_set_cursor(0, { 14, 0 })

            require("r.rmd").next_chunk()

            local cursor = vim.api.nvim_win_get_cursor(0)

            assert.same({ 22, 0 }, cursor, "Cursor did not move to the next chunk")
        end
    )
end)
