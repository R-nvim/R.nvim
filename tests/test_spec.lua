local parsers = require("nvim-treesitter.parsers")
local assert = require("luassert")

describe("Tree-sitter R parser", function()
    it("should parse an R file", function()
        -- Configure Tree-sitter for R and ensure parsers are installed

        -- Ensure the R parser is installed
        local parser_config = parsers.get_parser_configs()
        assert(parser_config.r, "R parser is not installed")

        -- Set up the R code and buffer. This is a simple example looking at the format_numbers() function
        local r_code = [[
            x <- 1:10
            y <- x^2
            seq(1, 10, by = 2)
        ]]

        -- Trim spaces from lines
        local trimmed_lines = {}
        for line in r_code:gmatch("[^\n]+") do
            table.insert(trimmed_lines, line:match("^%s*(.-)%s*$"))
        end

        -- Create buffer, set lines, and configure filetype
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, trimmed_lines)
        vim.api.nvim_buf_set_option(bufnr, "filetype", "r")

        -- Check that lines were set successfully and the parser works
        local parser = parsers.get_parser(bufnr, "r")
        local tree = parser:parse()[1] -- Get the first tree
        local root = tree:root()

        -- Optionally check or assert on the syntax tree or node
        assert(root, "Root of the syntax tree is nil")

        -- Set the created buffer as the current buffer
        vim.api.nvim_set_current_buf(bufnr)

        require("r.format.numbers").formatnum()

        local result_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

        local expected_result = {
            "x <- 1L:10L",
            "y <- x^2L",
            "seq(1L, 10L, by = 2L)",
            "",
        }

        assert.same(
            expected_result,
            result_lines,
            "Formatted code did not match expected result"
        )
    end)
end)
