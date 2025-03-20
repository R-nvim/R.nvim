local parsers = require("nvim-treesitter.parsers")
local assert = require("luassert")
local test_utils = require("./utils")

describe("formatnum()", function()
    it(
        "Replaces all implicit numbers in the current R buffer with explicit integers",
        function()
            local bufnr = test_utils.create_r_buffer_from_file("tests/fixtures/numbers.R")

            local parser = parsers.get_parser(bufnr, "r")
            local tree = parser:parse()[1] -- Get the first tree
            local root = tree:root()

            assert(root, "Root of the syntax tree is nil")

            vim.api.nvim_set_current_buf(bufnr)
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
                "Formatted code did not match expected result"
            )
        end
    )
end)
