--- Workspace indexing for R.nvim LSP
--- Manages centralized symbol cache across all R files in the workspace

local M = {}

local utils = require("r.lsp.utils")

--- Cache for workspace definitions: { symbol_name -> [{file, line, col}] }
---@type table<string, table[]>
local workspace_index = {}

--- File modification times for cache invalidation
---@type table<string, number>
local file_mtimes = {}

--- Whether initial indexing has been done
local indexed = false

--- Index all R files in the workspace
---@param force? boolean Force reindexing even if already done
function M.index_workspace(force)
    if indexed and not force then return end

    local cwd = vim.fn.getcwd()
    local files = {}
    utils.find_r_files(cwd, files)

    workspace_index = {}
    file_mtimes = {}

    for _, filepath in ipairs(files) do
        local stat = vim.uv.fs_stat(filepath)
        if stat then
            file_mtimes[filepath] = stat.mtime.sec

            local definitions = utils.parse_file_definitions(filepath)
            for symbol, locations in pairs(definitions) do
                if not workspace_index[symbol] then workspace_index[symbol] = {} end
                for _, loc in ipairs(locations) do
                    table.insert(workspace_index[symbol], loc)
                end
            end
        end
    end

    indexed = true
end

--- Update index for a single file
---@param filepath string
function M.update_file_index(filepath)
    if not indexed then return end

    local stat = vim.uv.fs_stat(filepath)
    if not stat then return end

    local normalized_filepath = utils.normalize_path(filepath)

    for symbol, locations in pairs(workspace_index) do
        workspace_index[symbol] = vim.tbl_filter(function(loc)
            local normalized_loc = utils.normalize_path(loc.file)
            return normalized_loc ~= normalized_filepath
        end, locations)
        if #workspace_index[symbol] == 0 then workspace_index[symbol] = nil end
    end

    file_mtimes[normalized_filepath] = stat.mtime.sec
    local definitions = utils.parse_file_definitions(normalized_filepath)
    for symbol, locations in pairs(definitions) do
        if not workspace_index[symbol] then workspace_index[symbol] = {} end
        for _, loc in ipairs(locations) do
            table.insert(workspace_index[symbol], loc)
        end
    end
end

--- Update workspace index from modified buffer content
--- Used by references.lua and implementation.lua for live buffer sync
function M.update_modified_buffer()
    local current_file = vim.api.nvim_buf_get_name(0)
    if not vim.bo.modified or current_file == "" then return end

    local normalized_file = utils.normalize_path(current_file)

    for symbol, locations in pairs(workspace_index) do
        workspace_index[symbol] = vim.tbl_filter(function(loc)
            local normalized_loc = utils.normalize_path(loc.file)
            return normalized_loc ~= normalized_file
        end, locations)
        if #workspace_index[symbol] == 0 then workspace_index[symbol] = nil end
    end

    local symbols = utils.extract_symbols(0)
    for _, sym in ipairs(symbols) do
        if not workspace_index[sym.name] then workspace_index[sym.name] = {} end
        table.insert(workspace_index[sym.name], {
            file = normalized_file,
            line = sym.name_start_row,
            col = sym.name_start_col,
        })
    end
end

--- Get definitions for a symbol from workspace index
---@param symbol string The symbol to find
---@return table[] List of locations {file, line, col}
function M.get_definitions(symbol)
    M.index_workspace()
    return workspace_index[symbol] or {}
end

--- Find all symbols matching a pattern
---@param pattern string Lua pattern to match against symbol names
---@return table[] List of locations {file, line, col}
function M.find_symbols_matching(pattern)
    M.index_workspace()
    local results = {}
    for symbol, locations in pairs(workspace_index) do
        if symbol:match(pattern) then
            for _, loc in ipairs(locations) do
                table.insert(results, loc)
            end
        end
    end
    return results
end

--- Rebuild the entire workspace index
function M.rebuild_index()
    indexed = false
    M.index_workspace(true)
    vim.notify("R workspace index rebuilt", vim.log.levels.INFO)
end

--- Setup autocommand to update index on file save
function M.setup()
    vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = { "*.R", "*.r", "*.Rmd", "*.rmd", "*.qmd" },
        callback = function(ev) M.update_file_index(ev.file) end,
        desc = "Update R definition index on save",
    })
end

return M
