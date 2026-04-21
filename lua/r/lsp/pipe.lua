--- Pipe chain column resolution for R.nvim LSP
--- Handles tidyverse data-masking semantics where named arguments
--- in functions like mutate() define columns accessible in subsequent
--- pipe steps (|> and %>%).
---@module 'r.lsp.pipe'

local M = {}

local ast = require("r.lsp.ast")

--- Functions whose named arguments create columns (data-masking verbs)
---@type table<string, boolean>
local column_defining_fns = {
    mutate = true,
    transmute = true,
    summarize = true,
    summarise = true,
    reframe = true,
    rename = true,
    count = true,
    add_count = true,
}

--- Check if a binary_operator node is a pipe operator (|> or %>%)
---@param node TSNode
---@param bufnr integer
---@return boolean
local function is_pipe_operator(node, bufnr)
    if node:type() ~= "binary_operator" then return false end
    local op = node:field("operator")[1]
    if not op then return false end
    local text = vim.treesitter.get_node_text(op, bufnr)
    return text == "|>" or text == "%>%"
end

--- Check if an identifier node is the name field of a column-defining argument
--- (e.g. `dir` in `mutate(dir = dirname(path))`)
---@param node TSNode identifier node
---@param bufnr integer
---@return boolean
local function is_column_definition(node, bufnr)
    local arg_node = node:parent()
    if not arg_node or arg_node:type() ~= "argument" then return false end

    local name_nodes = arg_node:field("name")
    if #name_nodes == 0 or name_nodes[1]:id() ~= node:id() then return false end

    -- Walk up: argument -> arguments -> call
    local args_node = arg_node:parent()
    local call_node = args_node and args_node:parent()
    if not call_node or call_node:type() ~= "call" then return false end

    local fn = call_node:field("function")[1]
    if not fn then return false end
    local fn_name = vim.treesitter.get_node_text(fn, bufnr)
    return column_defining_fns[fn_name] == true
end

--- Check if an identifier is a non-column argument name
--- (e.g. `glob` in `dir_ls(glob = "*.png")`)
---@param node TSNode identifier node
---@param bufnr integer
---@return boolean
local function is_regular_argument_name(node, bufnr)
    local arg_node = node:parent()
    if not arg_node or arg_node:type() ~= "argument" then return false end

    local name_nodes = arg_node:field("name")
    if #name_nodes == 0 or name_nodes[1]:id() ~= node:id() then return false end

    return not is_column_definition(node, bufnr)
end

--- Check if an identifier is a function name position
--- (e.g. `count` in `count(category)`)
---@param node TSNode identifier node
---@return boolean
local function is_function_name(node)
    local parent = node:parent()
    if not parent or parent:type() ~= "call" then return false end
    local fn_nodes = parent:field("function")
    return #fn_nodes > 0 and fn_nodes[1]:id() == node:id()
end

--- Walk up from a position to find the root of the enclosing pipe chain.
--- Stops at the first non-pipe ancestor after finding a pipe, so nested
--- pipe chains (e.g. inside map()) are handled correctly.
---@param bufnr integer Buffer number
---@param row integer 0-indexed row
---@param col integer 0-indexed column
---@return TSNode? pipe_root The root binary_operator of the pipe chain
function M.get_pipe_root(bufnr, row, col)
    local node = ast.node_at_position(bufnr, row, col)
    if not node then return nil end

    local pipe_root = nil
    local current = node

    while current do
        if is_pipe_operator(current, bufnr) then
            pipe_root = current
        elseif pipe_root then
            break
        end
        current = current:parent()
    end

    return pipe_root
end

--- Collect the set of column names defined in a pipe chain
---@param bufnr integer Buffer number
---@param pipe_root TSNode Root of pipe chain
---@return table<string, boolean> Set of column names
function M.collect_column_names(bufnr, pipe_root)
    local names = {}

    local function walk(node)
        if node:type() == "identifier" and is_column_definition(node, bufnr) then
            local text = vim.treesitter.get_node_text(node, bufnr)
            names[text] = true
        end
        for child in node:iter_children() do
            if child:named() then walk(child) end
        end
    end

    walk(pipe_root)
    return names
end

--- Find all occurrences of a symbol within a pipe chain.
--- Includes column-defining argument names but excludes regular argument
--- names and function name positions.
---@param bufnr integer Buffer number
---@param pipe_root TSNode Root of pipe chain
---@param symbol string Symbol to search for
---@return table[] List of {file, line, col, end_col}
function M.find_all_occurrences(bufnr, pipe_root, symbol)
    local file = vim.api.nvim_buf_get_name(bufnr)
    local refs = {}

    local function walk(node)
        if node:type() == "identifier" then
            local text = vim.treesitter.get_node_text(node, bufnr)
            if
                text == symbol
                and not is_regular_argument_name(node, bufnr)
                and not is_function_name(node)
            then
                local start_row, start_col = node:start()
                local _, end_col = node:end_()
                table.insert(refs, {
                    file = file,
                    line = start_row,
                    col = start_col,
                    end_col = end_col,
                })
            end
        end
        for child in node:iter_children() do
            if child:named() then walk(child) end
        end
    end

    walk(pipe_root)
    return refs
end

--- Resolve a symbol as a pipe column definition.
--- Returns the location of the first (earliest) column definition in the chain.
---@param bufnr integer Buffer number
---@param row integer 0-indexed row
---@param col integer 0-indexed column
---@param symbol string Symbol to resolve
---@return {file: string, line: integer, col: integer}? Location or nil
function M.resolve_column(bufnr, row, col, symbol)
    local pipe_root = M.get_pipe_root(bufnr, row, col)
    if not pipe_root then return nil end

    local col_names = M.collect_column_names(bufnr, pipe_root)
    if not col_names[symbol] then return nil end

    local file = vim.api.nvim_buf_get_name(bufnr)
    local best = nil

    local function walk(node)
        if node:type() == "identifier" and is_column_definition(node, bufnr) then
            local text = vim.treesitter.get_node_text(node, bufnr)
            if text == symbol then
                local start_row, start_col = node:start()
                if
                    not best
                    or start_row < best.line
                    or (start_row == best.line and start_col < best.col)
                then
                    best = { file = file, line = start_row, col = start_col }
                end
            end
        end
        for child in node:iter_children() do
            if child:named() then walk(child) end
        end
    end

    walk(pipe_root)
    return best
end

--- Find all locations for a symbol in a pipe chain context.
--- Returns nil if not in a pipe chain or if the symbol is not a pipe column.
---@param bufnr integer Buffer number
---@param row integer 0-indexed row
---@param col integer 0-indexed column
---@param symbol string Symbol to search for
---@return table[]? List of {file, line, col, end_col} or nil
function M.find_locations(bufnr, row, col, symbol)
    local pipe_root = M.get_pipe_root(bufnr, row, col)
    if not pipe_root then return nil end

    local col_names = M.collect_column_names(bufnr, pipe_root)
    if not col_names[symbol] then return nil end

    return M.find_all_occurrences(bufnr, pipe_root, symbol)
end

return M
