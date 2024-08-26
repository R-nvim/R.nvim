-- There are two types of subsetting expressions in R: $ and [.
-- These functions are used to replace the subsetting expressions in R.
-- First case, when using the $ operator: df$var -> df[["var"]]
-- Second case, when using the [ operator: vec[1] -> vec[[1]]
-- It supports multiple subsetting and nested expressions: df$var[1] -> df[["var"]][[1]]

-- TODO: just juste the first level of subsetting for the $ operator.

local warn = require("r").warn
local M = {}

local parsers = require("nvim-treesitter.parsers")

-- Define the Treesitter query for capturing nodes
local query = [[
(extract_operator
    (identifier)
    (extract_operator
        (identifier)
        (extract_operator
            (identifier)
        )*
    )*
) @dollar_operator

(subset
    (identifier)*
    (arguments
      (argument
        (_) )) @single_bracket)
]]

--- Build a replacement string for a given node by traversing its child nodes
---@param node userdata: The Treesitter node to traverse
---@param bufnr number: The buffer number
---@return string: The constructed replacement string
local function build_extract_operator_replacement(node, bufnr)
    local identifiers = {}

    -- Function to recursively collect identifier text
    local function collect_identifiers(inner_node)
        if inner_node:type() == "identifier" then
            local text = vim.treesitter.get_node_text(inner_node, bufnr)
            if text ~= "" then table.insert(identifiers, text) end
        else
            local child_count = inner_node:named_child_count()
            for i = 0, child_count - 1 do
                local child_node = inner_node:named_child(i)
                collect_identifiers(child_node)
            end
        end
    end

    -- Start collecting identifiers from the node
    collect_identifiers(node)

    -- Construct the replacement string, avoiding double wrapping
    local replacement = table.remove(identifiers, 1)
    for _, id in ipairs(identifiers) do
        replacement = string.format('%s[["%s"]]', replacement, id)
    end

    return replacement
end

--- Format extract_operator subsetting expressions
---@param node userdata: The Treesitter node to process
---@param bufnr number: The buffer number
---@return table: The replacement information for the node
local function process_extract_operator(node, bufnr)
    local replacement = build_extract_operator_replacement(node, bufnr)

    if replacement and node then
        local start_row, start_col, end_row, end_col = node:range()
        return {
            text_to_replace = vim.treesitter.get_node_text(node, bufnr),
            start_row = start_row,
            start_col = start_col,
            end_row = end_row,
            end_col = end_col,
            text = replacement,
        }
    end

    -- empty table
    return {}
end

--- Format subset subsetting expressions
---@param node userdata: The Treesitter node to process
---@param bufnr number: The buffer number
---@return table: The replacement information for the node
local function process_subset(node, bufnr)
    local value_node = node:named_child(0)

    if not value_node then return {} end

    -- Process only if the value is not a comma. This prevents
    -- processing when the brackets are used for subsetting a matrix.
    -- We can verify this by checking if the node has a single child.
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

--- Formats subsetting expressions in the current buffer using Treesitter and
--- parses the buffer to find and replace specific patterns defined in a
--- Treesitter query
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

    for id, node, _ in query_obj:iter_captures(root, bufnr, 0, -1) do
        local replacement

        if query_obj.captures[id] == "dollar_operator" then
            -- Get the parent node
            local parent = node:parent()

            -- Check if the parent is an extract_operator
            if parent and parent:type() ~= "extract_operator" then
                replacement = process_extract_operator(node, bufnr)
            end
        elseif query_obj.captures[id] == "single_bracket" then
            replacement = process_subset(node, bufnr)
        end

        if replacement then table.insert(replacements, replacement) end
    end

    -- Apply replacements in reverse order
    -- vim.print(replacements)
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
