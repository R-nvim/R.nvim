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

--- Search for definition in enclosing scopes using custom definitions query
--- This handles <<- assignments which aren't captured by tree-sitter locals query
---@param symbol string The symbol to find
---@param bufnr integer Buffer number
---@param row integer Cursor row (0-indexed)
---@param col integer Cursor column (0-indexed)
---@return table? Location {file, line, col} or nil
local function find_in_enclosing_scopes(symbol, bufnr, row, col)
    local ast = require("r.lsp.ast")
    local queries = require("r.lsp.queries")

    local _, root = ast.get_parser_and_root(bufnr)
    if not root then return nil end

    local node = ast.node_at_position(bufnr, row, col)
    if not node then return nil end

    local query = queries.get("definitions")
    if not query then return nil end

    local file = vim.api.nvim_buf_get_name(bufnr)

    -- Collect enclosing function scopes
    local scopes = ast.collect_ancestors(node, "function_definition")
    table.insert(scopes, root) -- Add file scope

    -- Search each scope from innermost to outermost
    for _, scope_node in ipairs(scopes) do
        local search_node = scope_node
        if scope_node:type() == "function_definition" then
            search_node = scope_node:field("body")[1] or scope_node
        end

        local matches = {}
        for id, match_node in query:iter_captures(search_node, bufnr) do
            local capture_name = query.captures[id]
            if capture_name == "name" or capture_name == "var_name" then
                local text = vim.treesitter.get_node_text(match_node, bufnr)
                if text == symbol then
                    local start_row, start_col = match_node:start()
                    -- Only consider assignments before the cursor
                    if start_row < row or (start_row == row and start_col <= col) then
                        table.insert(matches, {
                            file = file,
                            line = start_row,
                            col = start_col,
                        })
                    end
                end
            end
        end

        -- Return the closest match before cursor in this scope
        if #matches > 0 then
            table.sort(matches, function(a, b)
                if a.line ~= b.line then return a.line > b.line end
                return a.col > b.col
            end)
            return matches[1]
        end
    end

    return nil
end

--- Scope-aware definition search
--- First tries scope.lua (for local definitions), then falls back to
--- searching enclosing scopes with custom query (for <<- assignments)
---@param symbol string The symbol to find
---@param bufnr integer Buffer number
---@param row integer Cursor row (0-indexed)
---@param col integer Cursor column (0-indexed)
---@return table? Location {file, line, col} or nil
local function find_in_scope(symbol, bufnr, row, col)
    -- First try scope.lua for standard local definitions
    local scope_ctx = scope.get_scope_at_position(bufnr, row, col)
    if scope_ctx then
        local def = scope.resolve_symbol(symbol, scope_ctx)
        if def then
            return {
                file = def.location.file,
                line = def.location.line,
                col = def.location.col,
            }
        end
    end

    -- Fall back to searching enclosing scopes with custom query
    -- This handles <<- assignments and other edge cases
    return find_in_enclosing_scopes(symbol, bufnr, row, col)
end

--- Parse a potentially qualified symbol (pkg::fn or pkg:::fn)
---@param symbol string
---@return string? pkg Package name or nil
---@return string fn Function/symbol name
---@return boolean internal Whether it's an internal symbol (:::)
local function parse_qualified_name(symbol)
    -- TODO: Use tree-sitter for more robust parsing
    local pkg, fn = symbol:match("^([%w%.]+):::(.+)$")
    if pkg then return pkg, fn, true end
    pkg, fn = symbol:match("^([%w%.]+)::(.+)$")
    if pkg then return pkg, fn, false end
    return nil, symbol, false
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
    local word = require("r.cursor").get_keyword()

    if word == "" then
        require("r.lsp").send_msg({ code = "N" .. req_id })
        return
    end

    local pkg, symbol, _ = parse_qualified_name(word)

    -- 1. Try scope-aware search in current buffer first
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1 -- Convert to 0-indexed
    local col = cursor_pos[2]

    local scope_match = find_in_scope(symbol, 0, row, col)
    if scope_match then
        local msg = {
            code = "D",
            orig_id = req_id,
            uri = "file://" .. scope_match.file,
            line = scope_match.line,
            col = scope_match.col,
        }
        require("r.lsp").send_msg(msg)
        return
    end

    -- 2. Check workspace index for other files (using centralized workspace.lua)
    local workspace_locations = workspace.get_definitions(symbol)
    if #workspace_locations > 0 then
        if #workspace_locations == 1 then
            -- Single result: send as Location
            local loc = workspace_locations[1]
            local msg = {
                code = "D",
                orig_id = req_id,
                uri = "file://" .. loc.file,
                line = loc.line,
                col = loc.col,
            }
            require("r.lsp").send_msg(msg)
        else
            -- Multiple results: send as Location[]
            local msg = {
                code = "D",
                orig_id = req_id,
                locations = workspace_locations,
            }
            require("r.lsp").send_msg(msg)
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

    require("r.lsp").send_msg({ code = "N" .. req_id })
end

--- Handle definition response from nvimcom
--- Called when nvimcom sends back source location
---@param req_id string Request ID
---@param filepath string? File path or nil
---@param line integer? Line number (1-indexed from R)
---@param col integer? Column number
function M.handle_definition_response(req_id, filepath, line, col)
    if filepath and filepath ~= "" then
        require("r.lsp").send_msg({
            code = "D",
            orig_id = req_id,
            uri = "file://" .. filepath,
            line = (line or 1) - 1, -- Convert to 0-indexed
            col = (col or 1) - 1,
        })
    else
        require("r.lsp").send_msg({ code = "N" .. req_id })
    end
end

return M
