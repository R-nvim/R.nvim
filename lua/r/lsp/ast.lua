--- AST traversal utilities for R code analysis
--- Provides high-level functions for navigating the tree-sitter AST,
--- eliminating the need for manual node iteration
---@module 'r.lsp.ast'

local M = {}

--- Get parser and root node for a buffer (cached, error-handled)
---@param bufnr integer Buffer number
---@param lang? string Language (default "r")
---@return vim.treesitter.LanguageTree?, TSNode?
function M.get_parser_and_root(bufnr, lang)
    lang = lang or "r"

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok or not parser then
        return nil, nil
    end

    local tree = parser:parse()[1]
    if not tree then
        return nil, nil
    end

    return parser, tree:root()
end

--- Find node at position
---@param bufnr integer Buffer number
---@param row integer 0-indexed row
---@param col integer 0-indexed column
---@return TSNode?
function M.node_at_position(bufnr, row, col)
    local _, root = M.get_parser_and_root(bufnr)
    if not root then
        return nil
    end

    return root:descendant_for_range(row, col, row, col)
end

--- Walk up tree to find ancestor of type
---@param node TSNode Starting node
---@param node_types string|string[] Single type or array of types
---@return TSNode?
function M.find_ancestor(node, node_types)
    if type(node_types) == "string" then
        node_types = { node_types }
    end

    local current = node:parent()
    while current do
        for _, node_type in ipairs(node_types) do
            if current:type() == node_type then
                return current
            end
        end
        current = current:parent()
    end

    return nil
end

--- Walk up tree collecting all ancestors of type
---@param node TSNode Starting node
---@param node_type string Node type to collect
---@return TSNode[]
function M.collect_ancestors(node, node_type)
    local ancestors = {}
    local current = node:parent()

    while current do
        if current:type() == node_type then
            table.insert(ancestors, current)
        end
        current = current:parent()
    end

    return ancestors
end

--- Get all children of specific type
---@param node TSNode Parent node
---@param child_type string Child type to find
---@return TSNode[]
function M.get_children_of_type(node, child_type)
    local children = {}

    for child in node:iter_children() do
        if child:type() == child_type then
            table.insert(children, child)
        end
    end

    return children
end

--- Extract first argument from call node using tree-sitter query
---@param bufnr integer Buffer number
---@param call_node TSNode Call node
---@return string? Argument text
function M.get_first_call_argument(bufnr, call_node)
    if call_node:type() ~= "call" then
        return nil
    end

    -- Get arguments node
    local args_nodes = M.get_children_of_type(call_node, "arguments")
    if #args_nodes == 0 then
        return nil
    end

    local arguments = args_nodes[1]

    -- Get first argument
    for child in arguments:iter_children() do
        if child:type() == "argument" then
            -- Get the value of the argument
            for arg_child in child:iter_children() do
                if arg_child:named() and arg_child:type() ~= "identifier" then
                    -- Skip calls and complex expressions
                    if arg_child:type() == "call" then
                        return nil
                    end
                    if arg_child:type() == "identifier" then
                        return vim.treesitter.get_node_text(arg_child, bufnr)
                    end
                elseif arg_child:type() == "identifier" then
                    return vim.treesitter.get_node_text(arg_child, bufnr)
                end
            end
        end
    end

    return nil
end

--- Find call to specific function in binary chain
---@param bufnr integer Buffer number
---@param start_node TSNode Starting node
---@param function_name string Function name to find
---@return TSNode? Call node
function M.find_call_in_chain(bufnr, start_node, function_name)
    -- Check if start_node is a call to the function
    if start_node:type() == "call" then
        for child in start_node:iter_children() do
            if child:type() == "identifier" then
                local fn_name = vim.treesitter.get_node_text(child, bufnr)
                if fn_name == function_name then
                    return start_node
                end
            end
        end
    end

    -- If it's a binary_operator, recursively search children
    if start_node:type() == "binary_operator" then
        for child in start_node:iter_children() do
            if child:named() then
                local result = M.find_call_in_chain(bufnr, child, function_name)
                if result then
                    return result
                end
            end
        end
    end

    return nil
end

--- Check if position is within comment or string
---@param bufnr integer Buffer number
---@param row integer 0-indexed row
---@param col integer 0-indexed column
---@return boolean in_comment, boolean in_string
function M.is_in_comment_or_string(bufnr, row, col)
    local node = M.node_at_position(bufnr, row, col)
    if not node then
        return false, false
    end

    local in_comment = false
    local in_string = false

    -- Walk up to check if we're in a comment or string
    ---@type TSNode?
    local current = node
    while current do
        local node_type = current:type()
        if node_type == "comment" then
            in_comment = true
        elseif node_type:match("string") then
            in_string = true
        end
        current = current:parent()
    end

    return in_comment, in_string
end

return M
