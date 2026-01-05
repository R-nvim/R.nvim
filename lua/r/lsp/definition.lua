--- LSP Goto Definition support for R.nvim
--- Provides textDocument/definition functionality with workspace-wide search
--- and package source resolution (similar to R languageserver behavior)

local M = {}

local scope = require("r.lsp.scope")
local workspace = require("r.lsp.workspace")
local utils = require("r.lsp.utils")

--- Find definitions in the current buffer (used by tests)
---@param symbol string The symbol to find
---@return table[] List of locations {file, line, col}
function M.find_in_current_buffer(symbol)
    local symbols = utils.extract_symbols(0, { symbol_name = symbol })

    local matches = {}
    for _, sym in ipairs(symbols) do
        table.insert(matches, {
            file = sym.file,
            line = sym.name_start_row, -- 0-indexed
            col = sym.name_start_col, -- 0-indexed
        })
    end

    return matches
end

--- Scope-aware definition search using scope.lua
--- Handles both standard assignments (<-, =) and super-assignments (<<-)
---@param symbol string The symbol to find
---@param bufnr integer Buffer number
---@param row integer Cursor row (0-indexed)
---@param col integer Cursor column (0-indexed)
---@return table? Location {file, line, col} or nil
local function find_in_scope(symbol, bufnr, row, col)
    local scope_ctx = scope.get_scope_at_position(bufnr, row, col)
    if not scope_ctx then return nil end

    local def = scope.resolve_symbol(symbol, scope_ctx)
    if def then
        return {
            file = def.location.file,
            line = def.location.line,
            col = def.location.col,
        }
    end

    return nil
end

--- Parse a potentially qualified symbol using tree-sitter
--- Handles pkg::fn (public) and pkg:::fn (internal) namespace operators
---@param bufnr integer Buffer number
---@param row integer Cursor row (0-indexed)
---@param col integer Cursor column (0-indexed)
---@return string? pkg Package name or nil
---@return string symbol Function/symbol name
---@return boolean internal Whether it's an internal symbol (:::)
local function parse_qualified_name_at_cursor(bufnr, row, col)
    local ast = require("r.lsp.ast")

    local node = ast.node_at_position(bufnr, row, col)
    if not node then
        local word = require("r.cursor").get_keyword()
        return nil, word, false
    end

    -- Walk up to find if we're inside a namespace_operator
    local current = node
    while current do
        if current:type() == "namespace_operator" then
            local lhs = current:field("lhs")[1]
            local rhs = current:field("rhs")[1]
            local operator = current:field("operator")[1]

            if lhs and rhs then
                local pkg = vim.treesitter.get_node_text(lhs, bufnr)
                local symbol = vim.treesitter.get_node_text(rhs, bufnr)
                local is_internal = false

                if operator then
                    local op_text = vim.treesitter.get_node_text(operator, bufnr)
                    is_internal = (op_text == ":::")
                end

                return pkg, symbol, is_internal
            end
        end
        current = current:parent()
    end

    -- Not a qualified name, return the symbol under cursor
    local word = vim.treesitter.get_node_text(node, bufnr)
    -- If the node is too large (e.g., we're on whitespace), fall back to get_keyword
    if #word > 100 or word:match("%s") then
        word = require("r.cursor").get_keyword()
    end
    return nil, word, false
end

--- Find definition in R package source
--- Communicates with nvimcom to get source location
---@param pkg string Package name
---@param symbol string Function/object name
---@param req_id string Request ID for async response
function M.find_in_package(pkg, symbol, req_id)
    if vim.g.R_Nvim_status ~= 7 then
        -- R is not running, can't query packages
        return nil
    end

    -- Send request to nvimcom to get source reference
    local cmd =
        string.format("nvimcom:::send_definition('%s', '%s', '%s')", req_id, pkg, symbol)
    require("r.run").send_to_nvimcom("E", cmd)
    -- Response will be sent back asynchronously
    return "pending"
end

--- Main entry point for goto definition
--- Called from rnvimserver via client/exeRnvimCmd
---@param req_id string LSP request ID
function M.goto_definition(req_id)
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1 -- Convert to 0-indexed
    local col = cursor_pos[2]
    local bufnr = vim.api.nvim_get_current_buf()

    -- Parse qualified name using tree-sitter
    local pkg, symbol, _ = parse_qualified_name_at_cursor(bufnr, row, col)

    if not symbol or symbol == "" then
        utils.send_null(req_id)
        return
    end

    -- 1. Try scope-aware search in current buffer first
    local scope_match = find_in_scope(symbol, bufnr, row, col)
    if scope_match then
        utils.send_response("D", req_id, {
            uri = "file://" .. scope_match.file,
            line = scope_match.line,
            col = scope_match.col,
        })
        return
    end

    -- 2. Check workspace index for other files (using centralized workspace.lua)
    local workspace_locations = workspace.get_definitions(symbol)
    if #workspace_locations > 0 then
        if #workspace_locations == 1 then
            -- Single result: send as Location
            local loc = workspace_locations[1]
            utils.send_response("D", req_id, {
                uri = "file://" .. loc.file,
                line = loc.line,
                col = loc.col,
            })
        else
            -- Multiple results: send as Location[]
            utils.send_response("D", req_id, {
                locations = workspace_locations,
            })
        end
        return
    end

    -- 3. Try package lookup if R is running
    if vim.g.R_Nvim_status == 7 then
        -- If qualified (pkg::fn), use that package
        -- Otherwise, let nvimcom search loaded packages
        local target_pkg = pkg or ""
        M.find_in_package(target_pkg, symbol, req_id)
        return
    end

    utils.send_null(req_id)
end

--- Handle definition response from nvimcom
--- Called when nvimcom sends back source location
---@param req_id string Request ID
---@param filepath string? File path or nil
---@param line integer? Line number (1-indexed from R)
---@param col integer? Column number
function M.handle_definition_response(req_id, filepath, line, col)
    if filepath and filepath ~= "" then
        utils.send_response("D", req_id, {
            uri = "file://" .. filepath,
            line = (line or 1) - 1, -- Convert to 0-indexed
            col = (col or 1) - 1,
        })
    else
        utils.send_null(req_id)
    end
end

return M
