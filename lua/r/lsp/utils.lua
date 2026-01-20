--- Shared LSP utilities for R.nvim
--- Provides common functions for symbol extraction, tree-sitter queries, and file operations

local M = {}

--- Common symbol information structure
---@class SymbolInfo
---@field name string Symbol name
---@field kind integer Symbol kind (12=function, 13=variable)
---@field is_definition boolean Whether this is a definition
---@field file string File path
---@field name_start_row integer 0-indexed
---@field name_start_col integer 0-indexed
---@field name_end_row integer 0-indexed
---@field name_end_col integer 0-indexed
---@field def_start_row integer 0-indexed (full definition range)
---@field def_start_col integer 0-indexed
---@field def_end_row integer 0-indexed
---@field def_end_col integer 0-indexed
---@field detail string? Additional info (e.g., function parameters)

--- Check if a node is at the top level (not inside a function)
---@param node table Tree-sitter node
---@return boolean
local function is_top_level(node)
    local current = node:parent()
    while current do
        if current:type() == "function_definition" then
            return false
        end
        current = current:parent()
    end
    return true
end

--- Helper function to create a SymbolInfo table
local function create_symbol_info(
    name,
    kind,
    file,
    name_start_row,
    name_start_col,
    name_end_row,
    name_end_col,
    def_start_row,
    def_start_col,
    def_end_row,
    def_end_col,
    detail
)
    return {
        name = name,
        kind = kind,
        is_definition = true,
        file = file,
        name_start_row = name_start_row,
        name_start_col = name_start_col,
        name_end_row = name_end_row,
        name_end_col = name_end_col,
        def_start_row = def_start_row,
        def_start_col = def_start_col,
        def_end_row = def_end_row,
        def_end_col = def_end_col,
        detail = detail,
    }
end

--- Extract all symbols from a buffer (generic core function)
--- This is used by:
--- - find_in_buffer() for goto-definition
--- - parse_file_definitions() for workspace indexing
--- - extract_document_symbols() for textDocument/documentSymbol
--- - find_references() and find_implementations() for workspace search
---@param bufnr integer Buffer number
---@param options? {symbol_name: string?, top_level_only: boolean?} Optional filters
---@return SymbolInfo[]
function M.extract_symbols(bufnr, options)
    options = options or {}

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "r")
    if not ok or not parser then return {} end

    local tree = parser:parse()[1]
    if not tree then return {} end

    local root = tree:root()
    local query = require("r.lsp.queries").get("definitions")
    if not query then return {} end

    local symbols = {}
    local seen = {}
    local file = vim.api.nvim_buf_get_name(bufnr)

    for id, node in query:iter_captures(root, bufnr) do
        local capture_name = query.captures[id]

        -- Handle function definitions
        if capture_name == "definition" then
            local parent = node
            if parent and parent:type() == "binary_operator" then
                local lhs = parent:field("lhs")[1]
                local rhs = parent:field("rhs")[1]

                if
                    lhs
                    and rhs
                    and rhs:type() == "function_definition"
                    and (not options.top_level_only or is_top_level(parent))
                then
                    local name = vim.treesitter.get_node_text(lhs, bufnr)

                    -- Apply symbol name filter if provided
                    if not options.symbol_name or name == options.symbol_name then
                        local name_start_row, name_start_col = lhs:start()
                        local name_end_row, name_end_col = lhs:end_()
                        local def_start_row, def_start_col = parent:start()
                        local def_end_row, def_end_col = parent:end_()

                        -- Extract parameters for detail
                        local params = rhs:field("parameters")[1]
                        local param_text = ""
                        if params then
                            param_text = vim.treesitter.get_node_text(params, bufnr)
                        end

                        local key = string.format(
                            "%s:%d:%d",
                            name,
                            name_start_row,
                            name_start_col
                        )
                        if not seen[key] then
                            seen[key] = true
                            table.insert(
                                symbols,
                                create_symbol_info(
                                    name,
                                    12, -- Function
                                    file,
                                    name_start_row,
                                    name_start_col,
                                    name_end_row,
                                    name_end_col,
                                    def_start_row,
                                    def_start_col,
                                    def_end_row,
                                    def_end_col,
                                    param_text
                                )
                            )
                        end
                    end
                end
            end
        end

        -- Handle variable assignments (non-function)
        if capture_name == "var_definition" then
            local parent = node
            if parent and parent:type() == "binary_operator" then
                local lhs = parent:field("lhs")[1]
                local rhs = parent:field("rhs")[1]

                if
                    lhs
                    and rhs
                    and rhs:type() ~= "function_definition"
                    and (not options.top_level_only or is_top_level(parent))
                then
                    local name = vim.treesitter.get_node_text(lhs, bufnr)

                    -- Apply symbol name filter if provided
                    if not options.symbol_name or name == options.symbol_name then
                        local name_start_row, name_start_col = lhs:start()
                        local name_end_row, name_end_col = lhs:end_()
                        local def_start_row, def_start_col = parent:start()
                        local def_end_row, def_end_col = parent:end_()

                        local key = string.format(
                            "%s:%d:%d",
                            name,
                            name_start_row,
                            name_start_col
                        )
                        if not seen[key] then
                            seen[key] = true
                            table.insert(
                                symbols,
                                create_symbol_info(
                                    name,
                                    13, -- Variable
                                    file,
                                    name_start_row,
                                    name_start_col,
                                    name_end_row,
                                    name_end_col,
                                    def_start_row,
                                    def_start_col,
                                    def_end_row,
                                    def_end_col,
                                    nil
                                )
                            )
                        end
                    end
                end
            end
        end
    end

    return symbols
end

--- Parse an R file and extract all definitions
---@param filepath string Absolute path to the file
---@return table<string, table[]> Definitions map {symbol -> [{file, line, col}]}
function M.parse_file_definitions(filepath)
    local buffer = require("r.lsp.buffer")
    local definitions = {}

    local bufnr, _, cleanup = buffer.load_file_to_buffer(filepath)
    if not bufnr then return definitions end

    -- Only extract top-level definitions for workspace indexing
    local symbols = M.extract_symbols(bufnr, { top_level_only = true })
    for _, sym in ipairs(symbols) do
        if not definitions[sym.name] then definitions[sym.name] = {} end
        table.insert(definitions[sym.name], {
            file = filepath, -- Use provided filepath, not the temp buffer name
            line = sym.name_start_row,
            col = sym.name_start_col,
        })
    end

    if cleanup then cleanup() end
    return definitions
end

--- Recursively find R files in a directory
---@param dir string Directory path
---@param files table List to append files to
---@param max_depth? integer Maximum recursion depth (default 10)
---@param current_depth? integer Current depth
function M.find_r_files(dir, files, max_depth, current_depth)
    max_depth = max_depth or 10
    current_depth = current_depth or 0

    if current_depth > max_depth then return end

    local handle = vim.uv.fs_scandir(dir)
    if not handle then return end

    while true do
        local name, type = vim.uv.fs_scandir_next(handle)
        if not name then break end

        local full_path = dir .. "/" .. name

        if type == "directory" then
            -- Skip hidden directories and common non-source directories
            if not name:match("^%.") and name ~= "node_modules" and name ~= "renv" then
                M.find_r_files(full_path, files, max_depth, current_depth + 1)
            end
        elseif type == "file" then
            -- Match R source files
            if
                name:match("%.R$")
                or name:match("%.r$")
                or name:match("%.Rmd$")
                or name:match("%.rmd$")
                or name:match("%.qmd$")
            then
                table.insert(files, full_path)
            end
        end
    end
end

--- Normalize a file path to absolute form
---@param path string File path (relative or absolute)
---@return string Absolute path
function M.normalize_path(path) return vim.fn.fnamemodify(path, ":p") end

--- Send LSP response via message
---@param code string Message code ('D', 'R', 'I', 'Y')
---@param req_id string Request ID
---@param data table Response data
function M.send_response(code, req_id, data)
    local lsp = require("r.lsp")
    data.code = code
    data.orig_id = req_id
    lsp.send_msg(data)
end

--- Send null response (no results found)
---@param req_id string Request ID
function M.send_null(req_id)
    local lsp = require("r.lsp")
    lsp.send_msg({ code = "N" .. req_id })
end

--- Deduplicate location list by normalizing paths and removing duplicates
---@param locations table[] List of {file, line, col} tables
---@return table[] Deduplicated list with normalized paths
function M.deduplicate_locations(locations)
    local seen = {}
    local unique_locs = {}

    for _, loc in ipairs(locations) do
        local normalized_file = M.normalize_path(loc.file)
        local key = string.format("%s:%d:%d", normalized_file, loc.line, loc.col)

        if not seen[key] then
            seen[key] = true
            loc.file = normalized_file
            table.insert(unique_locs, loc)
        end
    end

    return unique_locs
end

--- Validate and get keyword at cursor with error handling
---@return string? keyword, string? error
function M.get_keyword_safe()
    local ok, word = pcall(require("r.cursor").get_keyword)
    if not ok then return nil, "Failed to get keyword" end
    if word == "" then return nil, "No keyword at cursor" end
    return word, nil
end

--- Prepare workspace (consolidated pattern)
---@param update_buffer? boolean Update modified buffer (default true)
function M.prepare_workspace(update_buffer)
    update_buffer = update_buffer ~= false

    local workspace = require("r.lsp.workspace")
    workspace.index_workspace()

    if update_buffer then workspace.update_modified_buffer() end
end

return M
