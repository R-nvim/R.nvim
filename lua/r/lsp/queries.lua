--- Tree-sitter query management for R.nvim LSP
--- Centralizes all tree-sitter queries with caching and convenient iteration utilities
---@module 'r.lsp.queries'

local M = {}

--- Query cache to avoid re-parsing
---@type table<string, vim.treesitter.Query>
local query_cache = {}

--- Query string definitions (copied from original utils.lua)
local query_strings = {
    definitions = [[
        ; Function assignments with <- operator
        (binary_operator
            lhs: (identifier) @name
            operator: "<-"
            rhs: (function_definition)) @definition

        ; Function assignments with <<- operator
        (binary_operator
            lhs: (identifier) @name
            operator: "<<-"
            rhs: (function_definition)) @definition

        ; Function assignments with = operator
        (binary_operator
            lhs: (identifier) @name
            operator: "="
            rhs: (function_definition)) @definition

        ; Variable assignments with <- (non-function)
        (binary_operator
            lhs: (identifier) @var_name
            operator: "<-"
            rhs: (_) @var_value) @var_definition

        ; Variable assignments with = (non-function)
        (binary_operator
            lhs: (identifier) @var_name
            operator: "="
            rhs: (_) @var_value) @var_definition
    ]],

    references = [[
        ; Capture ALL identifier nodes for reference tracking
        (identifier) @reference
    ]],

    implementations = [[
        ; S3 method pattern: funcname.classname <- function
        (binary_operator
            lhs: (identifier) @s3_method_name
            operator: "<-"
            rhs: (function_definition)) @s3_method

        ; S3 method pattern with = operator
        (binary_operator
            lhs: (identifier) @s3_method_name
            operator: "="
            rhs: (function_definition)) @s3_method

        ; S4 setMethod pattern
        (call
            function: (identifier) @setmethod_fn
            arguments: (arguments) @setmethod_args) @s4_method

        ; S4 setGeneric pattern
        (call
            function: (identifier) @setgeneric_fn
            arguments: (arguments) @setgeneric_args) @s4_generic

        ; UseMethod calls (defines S3 generics)
        (call
            function: (identifier) @usemethod_fn
            arguments: (arguments) @usemethod_args) @s3_generic
    ]],
}

--- Get or create a cached query
---@param query_name string Query name: "definitions"|"references"|"implementations"
---@return vim.treesitter.Query?
function M.get(query_name)
    -- Return cached query if exists
    if query_cache[query_name] then return query_cache[query_name] end

    -- Get query string
    local query_str = query_strings[query_name]
    if not query_str then
        vim.notify(string.format("Unknown query: %s", query_name), vim.log.levels.ERROR)
        return nil
    end

    -- Parse and cache query
    local ok, query = pcall(vim.treesitter.query.parse, "r", query_str)
    if not ok then
        vim.notify(
            string.format("Failed to parse query %s: %s", query_name, query),
            vim.log.levels.ERROR
        )
        return nil
    end

    query_cache[query_name] = query
    return query
end

--- Get query from custom queries/r/*.scm files (if they exist)
---@param query_file string Filename without .scm extension
---@return vim.treesitter.Query?
function M.get_custom(query_file)
    local ok, query = pcall(vim.treesitter.query.get, "r", query_file)
    if not ok then return nil end
    return query
end

--- Iterator for query captures with automatic parser handling
---@param bufnr integer Buffer number
---@param query_name string Query name
---@param root? TSNode Optional root node (if nil, will get from buffer)
---@return fun(): integer?, TSNode?, table?
function M.iter_captures(bufnr, query_name, root)
    local query = M.get(query_name)
    if not query then
        return function() return nil end
    end

    -- If root not provided, get it from buffer
    if not root then
        local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "r")
        if not ok or not parser then
            return function() return nil end
        end

        local tree = parser:parse()[1]
        if not tree then
            return function() return nil end
        end

        root = tree:root()
    end

    -- Return iterator
    local iter = query:iter_captures(root, bufnr)
    return function()
        local id, node = iter()
        if not id then return nil end

        local metadata = {
            capture_name = query.captures[id],
            capture_id = id,
        }

        return id, node, metadata
    end
end

--- Clear query cache (useful for testing or reloading)
function M.clear_cache() query_cache = {} end

return M
