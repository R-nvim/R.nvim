--- Scope Management Module for R.nvim (Refactored to use tree-sitter locals queries)
--- Provides proper scope tracking and symbol resolution for LSP features
--- Uses tree-sitter locals queries instead of manual scope building

local M = {}

--- Symbol definition with scope information
---@class SymbolDefinition
---@field name string Symbol name
---@field kind integer Symbol kind (12=function, 13=variable, 5=class, etc.)
---@field location {file: string, line: integer, col: integer} Definition location
---@field visibility "public" | "private" | "parameter" Visibility

--- Scope context (lightweight - just stores position info)
---@class ScopeContext
---@field bufnr number Buffer number
---@field row number Row position (0-indexed)
---@field col number Column position (0-indexed)
---@field scope_nodes table[] Tree-sitter scope nodes (innermost to outermost)

--- Get all enclosing scopes at a position
---@param bufnr number Buffer number
---@param row number Row (0-indexed)
---@param col number Column (0-indexed)
---@return table[] Array of tree-sitter scope nodes (innermost to outermost)
local function get_enclosing_scopes(bufnr, row, col)
    local ast = require("r.lsp.ast")

    local parser, root = ast.get_parser_and_root(bufnr)
    if not parser then
        return {}
    end

    local node = ast.node_at_position(bufnr, row, col)
    if not node then
        return {}
    end

    local scopes = ast.collect_ancestors(node, "function_definition")

    -- Add file-level scope (root) if not already included
    local has_root = false
    for _, scope in ipairs(scopes) do
        if scope == root then
            has_root = true
            break
        end
    end
    if not has_root then
        table.insert(scopes, root)
    end

    return scopes
end

--- Find a definition within a specific scope node using locals query
---@param bufnr number Buffer number
---@param scope_node table Tree-sitter node representing a scope
---@param symbol string Symbol name to find
---@param is_root_scope boolean Whether this is the root/file scope
---@return SymbolDefinition|nil
local function find_definition_with_locals(bufnr, scope_node, symbol, is_root_scope)
    local ast = require("r.lsp.ast")
    local query = vim.treesitter.query.get("r", "locals")
    if not query then return nil end

    local file = vim.api.nvim_buf_get_name(bufnr)

    for id, node in query:iter_captures(scope_node, bufnr) do
        if query.captures[id] == "local.definition" then
            local text = vim.treesitter.get_node_text(node, bufnr)
            if text == symbol then
                local is_parameter = ast.find_ancestor(node, { "parameter", "argument" }) ~= nil

                if not (is_parameter and is_root_scope) then
                    local start_row, start_col = node:start()

                    local kind = 13
                    local visibility = "private"

                    if is_parameter then
                        visibility = "parameter"
                    end

                    local binary_op = ast.find_ancestor(node, "binary_operator")
                    if binary_op then
                        local rhs = binary_op:field("rhs")[1]
                        if rhs and rhs:type() == "function_definition" then
                            kind = 12
                        end
                    end

                    if is_root_scope and not is_parameter then
                        visibility = "public"
                    end

                    return {
                        name = symbol,
                        kind = kind,
                        location = {
                            file = file,
                            line = start_row,
                            col = start_col,
                        },
                        visibility = visibility,
                    }
                end
            end
        end
    end

    return nil
end

--- Find a definition using custom definitions query (handles <<- operator)
--- The tree-sitter locals query doesn't capture <<- as it's a super-assignment
---@param bufnr number Buffer number
---@param scope_node table Tree-sitter node representing a scope
---@param symbol string Symbol name to find
---@param cursor_row number Cursor row for "before cursor" filtering
---@param cursor_col number Cursor column for "before cursor" filtering
---@param is_root_scope boolean Whether this is the root/file scope
---@return SymbolDefinition|nil
local function find_definition_with_custom_query(
    bufnr,
    scope_node,
    symbol,
    cursor_row,
    cursor_col,
    is_root_scope
)
    local ast = require("r.lsp.ast")
    local queries = require("r.lsp.queries")

    local query = queries.get("definitions")
    if not query then return nil end

    local file = vim.api.nvim_buf_get_name(bufnr)

    -- For function scopes, search the body
    local search_node = scope_node
    if scope_node:type() == "function_definition" then
        search_node = scope_node:field("body")[1] or scope_node
    end

    local matches = {}
    for id, node in query:iter_captures(search_node, bufnr) do
        local capture_name = query.captures[id]
        if capture_name == "name" or capture_name == "var_name" then
            local text = vim.treesitter.get_node_text(node, bufnr)
            if text == symbol then
                local start_row, start_col = node:start()
                -- Only consider assignments before the cursor
                if start_row < cursor_row or (start_row == cursor_row and start_col <= cursor_col) then
                    local kind = 13
                    local binary_op = ast.find_ancestor(node, "binary_operator")
                    if binary_op then
                        local rhs = binary_op:field("rhs")[1]
                        if rhs and rhs:type() == "function_definition" then
                            kind = 12
                        end
                    end

                    table.insert(matches, {
                        name = symbol,
                        kind = kind,
                        location = {
                            file = file,
                            line = start_row,
                            col = start_col,
                        },
                        visibility = is_root_scope and "public" or "private",
                        _row = start_row,
                        _col = start_col,
                    })
                end
            end
        end
    end

    -- Return the closest match before cursor
    if #matches > 0 then
        table.sort(matches, function(a, b)
            if a._row ~= b._row then return a._row > b._row end
            return a._col > b._col
        end)
        local result = matches[1]
        result._row = nil
        result._col = nil
        return result
    end

    return nil
end

--- Find a definition within a specific scope node
--- First tries the tree-sitter locals query, then falls back to custom query
--- for <<- assignments which aren't captured by locals
---@param bufnr number Buffer number
---@param scope_node table Tree-sitter node representing a scope
---@param symbol string Symbol name to find
---@param cursor_row? number Cursor row for custom query (optional)
---@param cursor_col? number Cursor column for custom query (optional)
---@return SymbolDefinition|nil
local function find_definition_in_scope(bufnr, scope_node, symbol, cursor_row, cursor_col)
    local ast = require("r.lsp.ast")
    local _, root = ast.get_parser_and_root(bufnr)
    local is_root_scope = (root and scope_node == root)

    -- First try the standard locals query
    local def = find_definition_with_locals(bufnr, scope_node, symbol, is_root_scope)
    if def then return def end

    -- Fall back to custom query for <<- and other edge cases
    if cursor_row and cursor_col then
        return find_definition_with_custom_query(
            bufnr,
            scope_node,
            symbol,
            cursor_row,
            cursor_col,
            is_root_scope
        )
    end

    return nil
end

--- Get scope context at a position
---@param bufnr number Buffer number
---@param row number Row (0-indexed)
---@param col number Column (0-indexed)
---@return ScopeContext|nil Scope context or nil if no scope found
function M.get_scope_at_position(bufnr, row, col)
    local scopes = get_enclosing_scopes(bufnr, row, col)

    if #scopes == 0 then return nil end

    return {
        bufnr = bufnr,
        row = row,
        col = col,
        scope_nodes = scopes,
    }
end

--- Resolve a symbol within a scope context
--- Searches from innermost to outermost scope
---@param symbol string Symbol name to resolve
---@param scope_context ScopeContext Scope context from get_scope_at_position
---@return SymbolDefinition|nil Symbol definition or nil if not found
function M.resolve_symbol(symbol, scope_context)
    if not scope_context or not scope_context.scope_nodes then return nil end

    -- Search scopes from innermost to outermost
    for _, func_node in ipairs(scope_context.scope_nodes) do
        local def = find_definition_in_scope(
            scope_context.bufnr,
            func_node,
            symbol,
            scope_context.row,
            scope_context.col
        )
        if def then return def end
    end

    return nil
end

return M
