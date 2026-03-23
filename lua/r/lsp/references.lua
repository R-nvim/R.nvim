--- Find references for R.nvim LSP
--- Provides textDocument/references functionality

local M = {}

local workspace = require("r.lsp.workspace")
local utils = require("r.lsp.utils")
local scope = require("r.lsp.scope")

--- Find all workspace references without scope filtering (fallback)
---@param symbol string Symbol name
---@param req_id string LSP request ID
---@param bufnr integer Source buffer number
local function find_all_workspace_references(symbol, req_id, bufnr)
    local ast = require("r.lsp.ast")

    -- Prepare workspace
    utils.prepare_workspace()

    local all_refs = {}

    local workspace_locations = workspace.get_definitions(symbol)
    for _, loc in ipairs(workspace_locations) do
        table.insert(all_refs, {
            file = loc.file,
            line = loc.line,
            col = loc.col,
            end_col = loc.col + #symbol,
        })
    end

    local query = require("r.lsp.queries").get("references")
    if query then
        local parser, root = ast.get_parser_and_root(bufnr)

        if parser and root then
            local file = vim.api.nvim_buf_get_name(bufnr)

            for _, node in query:iter_captures(root, bufnr) do
                local text = vim.treesitter.get_node_text(node, bufnr)
                if text == symbol then
                    local start_row, start_col = node:start()
                    local _, end_col = node:end_()
                    table.insert(all_refs, {
                        file = file,
                        line = start_row,
                        col = start_col,
                        end_col = end_col,
                    })
                end
            end
        end
    end

    all_refs = utils.deduplicate_locations(all_refs)

    if #all_refs > 0 then
        utils.send_response("R", req_id, { locations = all_refs })
    else
        utils.send_null(req_id)
    end
end

--- Find all references to a symbol across workspace (scope-aware)
---@param req_id string LSP request ID
---@param line integer 0-indexed row from LSP params
---@param col integer 0-indexed column from LSP params
---@param bufnr integer Source buffer number
function M.find_references(req_id, line, col, bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local row = line

    -- Get keyword from LSP position params
    local word, err = utils.get_word_at_bufpos(bufnr, row, col)
    if err or not word then
        utils.send_null(req_id)
        return
    end

    local current_scope = scope.get_scope_at_position(bufnr, row, col)
    if not current_scope then
        -- No scope found, fallback to workspace search
        find_all_workspace_references(word, req_id, bufnr)
        return
    end

    local target_definition = scope.resolve_symbol(word, current_scope)
    if not target_definition then
        -- Symbol not resolved in scope, fallback to workspace search
        -- This handles cases like add(2,3) where add is defined in other files
        find_all_workspace_references(word, req_id, bufnr)
        return
    end

    utils.prepare_workspace()

    local all_refs = {}

    local query = require("r.lsp.queries").get("references")
    if not query then
        utils.send_null(req_id)
        return
    end

    local ast = require("r.lsp.ast")
    local parser, root = ast.get_parser_and_root(bufnr)
    local file = vim.api.nvim_buf_get_name(bufnr)

    if parser and root then
        for _, node in query:iter_captures(root, bufnr) do
            local text = vim.treesitter.get_node_text(node, bufnr)
            if text == word then
                local start_row, start_col = node:start()
                local _, end_col = node:end_()

                local usage_scope =
                    scope.get_scope_at_position(bufnr, start_row, start_col)
                if usage_scope then
                    local resolved = scope.resolve_symbol(word, usage_scope)
                    if
                        resolved and utils.is_same_definition(resolved, target_definition)
                    then
                        table.insert(all_refs, {
                            file = file,
                            line = start_row,
                            col = start_col,
                            end_col = end_col,
                        })
                    end
                end
            end
        end
    end

    -- For public (file-level) symbols, also search workspace files for usages
    -- Cross-file references can only see public symbols
    if target_definition.visibility == "public" then
        local workspace_locations = workspace.get_definitions(word)
        local buffer = require("r.lsp.buffer")

        for _, loc in ipairs(workspace_locations) do
            if utils.normalize_path(loc.file) ~= utils.normalize_path(file) then
                local temp_bufnr, _, cleanup = buffer.load_file_to_buffer(loc.file)
                if temp_bufnr then
                    local node = ast.node_at_position(temp_bufnr, loc.line, loc.col)
                    if node then
                        local in_function = ast.find_ancestor(node, "function_definition")
                        if not in_function then
                            table.insert(all_refs, {
                                file = loc.file,
                                line = loc.line,
                                col = loc.col,
                                end_col = loc.col + #word,
                            })
                        end
                    end
                    if cleanup then cleanup() end
                end
            end
        end

        -- Search all workspace files for file-level usages only
        local cwd = vim.fn.getcwd()
        local files = {}
        utils.find_r_files(cwd, files)

        for _, filepath in ipairs(files) do
            if utils.normalize_path(filepath) ~= utils.normalize_path(file) then
                local temp_bufnr, _, cleanup = buffer.load_file_to_buffer(filepath)

                if temp_bufnr then
                    local _, temp_root = ast.get_parser_and_root(temp_bufnr)

                    if temp_root then
                        for _, node in query:iter_captures(temp_root, temp_bufnr) do
                            local text = vim.treesitter.get_node_text(node, temp_bufnr)
                            if text == word then
                                local in_function =
                                    ast.find_ancestor(node, "function_definition")
                                if not in_function then
                                    local start_row, start_col = node:start()
                                    local _, end_col = node:end_()
                                    table.insert(all_refs, {
                                        file = filepath,
                                        line = start_row,
                                        col = start_col,
                                        end_col = end_col,
                                    })
                                end
                            end
                        end
                    end

                    if cleanup then cleanup() end
                end
            end
        end
    end

    all_refs = utils.deduplicate_locations(all_refs)

    if #all_refs > 0 then
        utils.send_response("R", req_id, { locations = all_refs })
    else
        utils.send_null(req_id)
    end
end

return M
