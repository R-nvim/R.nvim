local assert = require("luassert")
local test_utils = require("./utils")

describe(
    "The split_path() function correctly splits a path into its components",
    function()
        local function setup_buffer(content, cursor_pos)
            local bufnr = test_utils.create_r_buffer_from_string(content, "r")
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_win_set_cursor(0, cursor_pos)
            return bufnr
        end

        local function test_split_path(content, cursor_pos, expected_result, description)
            it(description, function()
                local bufnr = setup_buffer(content, cursor_pos)

                -- Ensure R parser is loaded
                vim.treesitter.language.add("r")

                -- Get parser for the buffer
                local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "r")
                if not ok or not parser then
                    pending("treesitter parser for R is not available")
                    return
                end

                parser:parse()

                require("r.path").separate()

                local result_line = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
                assert.same(
                    expected_result,
                    result_line[1],
                    "The path was not split as expected"
                )
            end)
        end

        test_split_path(
            "path <- 'path/to/file.csv'",
            { 1, 13 },
            "path <- file.path('path', 'to', 'file.csv')",
            "splits a CSV file path correctly when the cursor is inside the path"
        )

        test_split_path(
            "url <- 'https://fakeurl.com/path/to/resource'",
            { 1, 14 },
            "url <- paste0('https://', 'fakeurl.com/', 'path/', 'to/', 'resource')",
            "splits a URL correctly when the cursor is inside the URL"
        )

        test_split_path(
            "path <- 'path/to/file.csv'",
            { 1, 0 },
            "path <- 'path/to/file.csv'",
            "does not change the path if the cursor is not inside the path"
        )
    end
)
