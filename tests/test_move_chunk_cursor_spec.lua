local assert = require("luassert")
local test_utils = require("./utils")

describe("Chunk motion functionality", function()
    local bufnr

    before_each(function()
        bufnr = test_utils.create_r_buffer_from_file("tests/fixtures/chunks.qmd")
        vim.api.nvim_set_current_buf(bufnr)
    end)

    local function test_cursor_movement(initial_pos, expected_pos, description)
        it(description, function()
            vim.api.nvim_win_set_cursor(0, initial_pos)
            require("r.rmd").next_chunk()
            local cursor = vim.api.nvim_win_get_cursor(0)
            assert.same(
                expected_pos,
                cursor,
                "Cursor did not move to the expected position"
            )
        end)
    end

    test_cursor_movement(
        { 7, 0 },
        { 22, 0 },
        "Moves the cursor to the next chunk, skipping headers with eval set to false"
    )

    test_cursor_movement(
        { 14, 0 },
        { 22, 0 },
        "Moves the cursor to the next chunk, even if the cursor is on a header with eval set to false"
    )

    test_cursor_movement(
        { 8, 0 },
        { 23, 0 },
        "Moves the cursor inside the next chunk while the cursor is inside a chunk"
    )
end)
