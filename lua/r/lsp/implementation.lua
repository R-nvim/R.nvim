--- Find implementations for R.nvim LSP
--- Provides textDocument/implementation functionality for S3/S4 methods

local M = {}

local workspace = require("r.lsp.workspace")
local utils = require("r.lsp.utils")

--- Find S3 method implementations for a generic function
---@param word string The generic function name
---@return table[] List of locations {file, line, col}
local function find_s3_methods(word)
    -- Pattern: word.* (e.g., print.default, print.factor)
    local pattern = "^" .. vim.pesc(word) .. "%."
    return workspace.find_symbols_matching(pattern)
end

--- Find implementations of a generic function (S3/S4 methods)
---@param req_id string LSP request ID
function M.find_implementations(req_id)
    -- Get keyword safely
    local word, err = utils.get_keyword_safe()
    if err then
        utils.send_null(req_id)
        return
    end

    -- Prepare workspace
    utils.prepare_workspace()

    local implementations = {}

    -- Strategy 1: Static analysis - find S3 methods (word.classname)
    implementations = find_s3_methods(word)

    -- Strategy 2: Dynamic lookup via nvimcom (if R is running)
    -- TODO: Implement async R query for runtime method discovery
    -- if vim.g.R_Nvim_status == 7 then
    --     local cmd = string.format(
    --         "nvimcom:::send_implementations('%s', '%s')",
    --         req_id, word
    --     )
    --     require("r.run").send_to_nvimcom("E", cmd)
    --     return
    -- end

    -- Return static results
    if #implementations > 0 then
        utils.send_response("I", req_id, { locations = implementations })
    else
        utils.send_null(req_id)
    end
end

return M
