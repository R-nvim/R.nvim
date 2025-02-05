-- There are two types of subsetting expressions in R: $ and [.
-- These functions are used to replace the subsetting expressions in R.
-- First case, when using the $ operator: df$var -> df[["var"]]
-- Second case, when using the [ operator: vec[1] -> vec[[1]]
local warn = require("r.log").warn
local M = {}

--- Formats subsetting in R files by replacing extraction operators and subsets.
-- @param bufnr The buffer number to format. Defaults to the current buffer.
M.formatsubsetting = function(bufnr)
    --- Replaces the extraction operator with the appropriate format.
    -- @param node The tree-sitter node representing the extraction operator.
    local function replace_extract_operator(node)
        local lhs_node = node:field("lhs")[1]
        local rhs_node = node:field("rhs")[1]

        if lhs_node and rhs_node then
            local lhs_text = vim.treesitter.get_node_text(lhs_node, bufnr)
            local rhs_text = vim.treesitter.get_node_text(rhs_node, bufnr)

            local start_row, start_col, end_row, end_col = node:range()
            local new_text = string.format('%s[["%s"]]', lhs_text, rhs_text)

            vim.api.nvim_buf_set_text(
                bufnr,
                start_row,
                start_col,
                end_row,
                end_col,
                { new_text }
            )
        end
    end

    --- Replaces the subset with the appropriate format.
    -- @param node The tree-sitter node representing the subset.
    local function replace_subset(node)
        local function_node = node:field("function")[1]
        local arguments_node = node:field("arguments")[1]

        if function_node and arguments_node then
            local function_text = vim.treesitter.get_node_text(function_node, bufnr)
            local argument_node = arguments_node:named_child(0)
            local value_node = argument_node:field("value")[1]
            local value_text = vim.treesitter.get_node_text(value_node, bufnr)

            local start_row, start_col, end_row, end_col = node:range()
            local new_text = string.format("%s[[%s]]", function_text, value_text)

            vim.api.nvim_buf_set_text(
                bufnr,
                start_row,
                start_col,
                end_row,
                end_col,
                { new_text }
            )
        end
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local filetype = vim.bo[bufnr].filetype
    if filetype ~= "r" and filetype ~= "quarto" and filetype ~= "rmd" then
        warn("This function is not available for " .. filetype .. " files.")
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1] - 1
    local col = cursor[2]

    local diagnostics = vim.diagnostic.get(bufnr, { lnum = line, col = col })

    for _, diagnostic in ipairs(diagnostics) do
        if
            diagnostic.lnum == line
            and diagnostic.col == col
            and diagnostic.code == "extraction_operator_linter"
        then
            break
        else
            warn("Cursor is not at an extraction operator.")
        end
    end

    local parser = vim.treesitter.get_parser(bufnr)
    if not parser then return end

    local ts_utils = require("nvim-treesitter.ts_utils")
    local node = ts_utils.get_node_at_cursor()

    if node:type() == "extract_operator" then
        replace_extract_operator(node)
    elseif node:type() == "arguments" then
        local parent = node:parent()
        if parent and parent:type() == "subset" then replace_subset(parent) end
    end
end

return M
