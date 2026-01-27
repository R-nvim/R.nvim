--- Document symbols extraction for R.nvim LSP
--- Provides textDocument/documentSymbol functionality

local M = {}

local utils = require("r.lsp.utils")

--- Check if range A contains range B
---@param a table Range with start and end positions
---@param b table Range with start and end positions
---@return boolean
local function range_contains(a, b)
    -- A contains B if A starts before or at B and ends after or at B
    local a_start = a.start.line * 100000 + a.start.character
    local a_end = a["end"].line * 100000 + a["end"].character
    local b_start = b.start.line * 100000 + b.start.character
    local b_end = b["end"].line * 100000 + b["end"].character

    return a_start < b_start and a_end >= b_end
end

--- Convert SymbolInfo to DocumentSymbol format
---@param sym table SymbolInfo
---@return table DocumentSymbol
local function to_document_symbol(sym)
    return {
        name = sym.name,
        detail = sym.detail,
        kind = sym.kind,
        range = {
            start = {
                line = sym.def_start_row,
                character = sym.def_start_col,
            },
            ["end"] = {
                line = sym.def_end_row,
                character = sym.def_end_col,
            },
        },
        selectionRange = {
            start = {
                line = sym.name_start_row,
                character = sym.name_start_col,
            },
            ["end"] = {
                line = sym.name_end_row,
                character = sym.name_end_col,
            },
        },
        children = {},
    }
end

--- Build hierarchical symbol tree from flat list
---@param symbols table[] List of DocumentSymbol objects (with children field)
---@return table[] Tree of DocumentSymbol objects
local function build_symbol_tree(symbols)
    if #symbols == 0 then return {} end

    -- Sort by range start (line, then character)
    table.sort(symbols, function(a, b)
        if a.range.start.line ~= b.range.start.line then
            return a.range.start.line < b.range.start.line
        end
        return a.range.start.character < b.range.start.character
    end)

    local root = {}
    local stack = {}

    for _, sym in ipairs(symbols) do
        -- Pop symbols from stack that don't contain this symbol
        while #stack > 0 and not range_contains(stack[#stack].range, sym.range) do
            table.remove(stack)
        end

        if #stack > 0 then
            -- This symbol is a child of the top of the stack
            table.insert(stack[#stack].children, sym)
        else
            -- This is a top-level symbol
            table.insert(root, sym)
        end

        -- Only functions (kind == 12) can have children (they define scopes)
        if sym.kind == 12 then table.insert(stack, sym) end
    end

    return root
end

--- Extract document symbols from the current buffer
---@param bufnr integer Buffer number
---@return table[] List of DocumentSymbol objects (hierarchical)
local function extract_document_symbols(bufnr)
    local symbols = utils.extract_symbols(bufnr)

    local document_symbols = {}
    for _, sym in ipairs(symbols) do
        table.insert(document_symbols, to_document_symbol(sym))
    end

    return build_symbol_tree(document_symbols)
end

--- Handle textDocument/documentSymbol request
---@param req_id string LSP request ID
function M.document_symbols(req_id)
    local symbols = extract_document_symbols(0)

    if #symbols > 0 then
        utils.send_response("Y", req_id, { symbols = symbols })
    else
        utils.send_null(req_id)
    end
end

return M
