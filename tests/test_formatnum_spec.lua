local assert = require("luassert")
local test_utils = require("./utils")

describe("formatnum()", function()
    local bufnr

    before_each(function()
        bufnr = test_utils.create_r_buffer_from_file("tests/fixtures/numbers.R")
        vim.api.nvim_set_current_buf(bufnr)
    end)

    it(
        "Replaces all implicit numbers in the current R buffer with explicit integers",
        function()
            -- Ensure R parser is loaded
            vim.treesitter.language.add("r")

            -- Get parser for the buffer
            local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "r")
            if not ok or not parser then
                pending("treesitter parser for R is not available")
                return
            end

            local tree = parser:parse()[1]
            local root = tree:root()

            assert(root, "Root of the syntax tree is nil")

            require("r.format.numbers").formatnum()

            local result_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

            local expected_result = {
                "x <- 1L:10L",
                "y <- x^2L",
                "seq(1L, 10L, by = 2L)",
            }

            assert.same(
                expected_result,
                result_lines,
                "The numbers in the buffer were not formatted as expected"
            )
        end
    )
end)
