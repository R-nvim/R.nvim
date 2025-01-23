-- There are two types of subsetting expressions in R: $ and [.
-- These functions are used to replace the subsetting expressions in R.
-- First case, when using the $ operator: df$var -> df[["var"]]
-- Second case, when using the [ operator: vec[1] -> vec[[1]]
-- It supports multiple subsetting and nested expressions: df$var[1] -> df[["var"]][[1]]

local warn = require("r.log").warn
local M = {}

local parsers = require("nvim-treesitter.parsers")

-- Define the Treesitter query for capturing nodes
local query = [[
(extract_operator) @extract_operator

(subset
    (identifier)*
    (arguments
      (argument
        (_) )) @single_bracket)
]]

--- Build a replacement string for extract_operator nodes.
--- This function formats subsetting expressions using the $ operator.
---@param node TSNode: The Treesitter node to process
---@param bufnr number: The buffer number
---@return table: Replacement information for the node
local function build_extract_operator_replacement(node, bufnr)
    local rhs_node = node:field("rhs")[1]

    if not rhs_node then return {} end

    local rhs_text = vim.treesitter.get_node_text(rhs_node, bufnr)
    local replacement_rhs = string.format('[["%s"]]', rhs_text)

    local start_row_rhs, start_col_rhs, end_row_rhs, end_col_rhs = rhs_node:range()

    return {
        start_row = start_row_rhs,
        start_col = start_col_rhs - 1,
        end_row = end_row_rhs,
        end_col = end_col_rhs,
        text = replacement_rhs,
    }
end

--- Format subset subsetting expressions
---@param node TSNode: The Treesitter node to process
---@param bufnr number: The buffer number
---@return table: Replacement information for the node
local function build_subset_replacement(node, bufnr)
    local value_node = node:named_child(0)

    if not value_node then return {} end

    if node:named_child_count() == 1 then
        local value = vim.treesitter.get_node_text(value_node, bufnr)
        local replacement = string.format("[[%s]]", value)
        local start_row, start_col, end_row, end_col = node:range()
        return {
            start_row = start_row,
            start_col = start_col,
            end_row = end_row,
            end_col = end_col,
            text = replacement,
        }
    end

    return {}
end

--- Formats subsetting expressions in the current buffer using Treesitter.
--- Parses the buffer to find and replace specific patterns defined in a Treesitter query.
---@param bufnr number: (optional) The buffer number to operate on; defaults to the current buffer if not provided
M.formatsubsetting = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    if vim.bo[bufnr].filetype ~= "r" then
        warn("This function is only available for R files.")
        return
    end

    local lang = parsers.get_buf_lang(bufnr)

    if not lang then return end

    local parser = parsers.get_parser(bufnr, lang)
    local tree = parser:parse()[1]
    local root = tree:root()

    -- Parse the query
    local query_obj = vim.treesitter.query.parse(lang, query)

    local replacements = {}

    -- Process extract_operator nodes
    for id, node, _ in query_obj:iter_captures(root, bufnr, 0, -1) do
        if query_obj.captures[id] == "extract_operator" then
            local replacement = build_extract_operator_replacement(node, bufnr)
            if next(replacement) then table.insert(replacements, replacement) end
        end
    end

    -- Sort replacements to apply the farthest right first
    table.sort(replacements, function(a, b)
        if a.start_row == b.start_row then return a.start_col > b.start_col end
        return a.start_row > b.start_row
    end)

    -- Apply the replacements for extract_operator
    for i = 1, #replacements do
        local r = replacements[i]
        vim.api.nvim_buf_set_text(
            bufnr,
            r.start_row,
            r.start_col,
            r.end_row,
            r.end_col,
            { r.text }
        )
    end

    -- Clear replacements and handle subset nodes
    replacements = {}

    for id, node, _ in query_obj:iter_captures(root, bufnr, 0, -1) do
        if query_obj.captures[id] == "single_bracket" then
            local replacement = build_subset_replacement(node, bufnr)
            if next(replacement) then table.insert(replacements, replacement) end
        end
    end

    -- Apply the replacements for subset
    for i = #replacements, 1, -1 do
        local r = replacements[i]
        vim.api.nvim_buf_set_text(
            bufnr,
            r.start_row,
            r.start_col,
            r.end_row,
            r.end_col,
            { r.text }
        )
    end
end

return M
