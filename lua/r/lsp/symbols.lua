--- Document symbols extraction for R.nvim LSP
--- Provides textDocument/documentSymbol functionality

local M = {}

local utils = require("r.lsp.utils")

--- Extract document symbols from the current buffer
---@param bufnr integer Buffer number
---@return table[] List of DocumentSymbol objects
local function extract_document_symbols(bufnr)
    local symbols = utils.extract_symbols(bufnr)

    local document_symbols = {}
    for _, sym in ipairs(symbols) do
        table.insert(document_symbols, {
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
        })
    end

    table.sort(
        document_symbols,
        function(a, b) return a.range.start.line < b.range.start.line end
    )

    return document_symbols
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
