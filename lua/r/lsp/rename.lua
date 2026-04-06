--- LSP rename for R.nvim
--- Provides textDocument/rename functionality

local M = {}

local utils = require("r.lsp.utils")

--- Rename all references to the symbol at the given position
---@param req_id string LSP request ID
---@param line integer 0-indexed row from LSP params
---@param col integer 0-indexed column from LSP params
---@param bufnr integer Source buffer number
---@param new_name string The replacement identifier
function M.rename_symbol(req_id, line, col, bufnr, new_name)
    local result = require("r.lsp.references").find_locations(line, col, bufnr)
    if not result or #result.locations == 0 then
        utils.send_null(req_id)
        return
    end

    -- If the symbol wasn't resolved in the local scope and has no definition
    -- anywhere in the project, it belongs to an external package. Renaming it
    -- locally would silently produce broken code, so refuse.
    if not result.resolved then
        local workspace = require("r.lsp.workspace")
        if #workspace.get_definitions(result.word) == 0 then
            utils.send_null(req_id)
            return
        end
    end

    -- Group edits by file URI into WorkspaceEdit.changes format
    local changes = {}
    for _, loc in ipairs(result.locations) do
        local uri = "file://" .. loc.file
        if not changes[uri] then changes[uri] = {} end
        table.insert(changes[uri], {
            range = {
                start = { line = loc.line, character = loc.col },
                ["end"] = { line = loc.line, character = loc.end_col },
            },
            newText = new_name,
        })
    end

    utils.send_response("X", req_id, { changes = changes })
end

return M
