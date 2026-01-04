--- LSP Goto Definition support for R.nvim
--- Provides textDocument/definition functionality with workspace-wide search
--- and package source resolution (similar to R languageserver behavior)

local M = {}

--- Cache for workspace definitions: { symbol_name -> [{file, line, col}] }
---@type table<string, table[]>
local workspace_index = {}

--- File modification times for cache invalidation
---@type table<string, number>
local file_mtimes = {}

--- Whether initial indexing has been done
local indexed = false

--- Extract all symbols from a buffer (generic core function)
--- This is used by:
--- - find_in_buffer() for goto-definition
--- - parse_file_definitions() for workspace indexing
--- - extract_document_symbols() for textDocument/documentSymbol
--- - (future) find_all_references() for rename/references
---@param bufnr integer Buffer number
---@param options? {symbol_name: string?} Optional filter by symbol name
---@return SymbolInfo[]
local function extract_symbols(bufnr, options)
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

                if lhs and rhs and rhs:type() == "function_definition" then
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
                            table.insert(symbols, {
                                name = name,
                                kind = 12, -- Function
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
                                detail = param_text,
                            })
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

                -- Skip if it's a function (already handled above)
                if lhs and rhs and rhs:type() ~= "function_definition" then
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
                            table.insert(symbols, {
                                name = name,
                                kind = 13, -- Variable
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
                                detail = nil,
                            })
                        end
                    end
                end
            end
        end
    end

    return symbols
end

--- Find definitions in a buffer using tree-sitter
---@param symbol string The symbol to find
---@param bufnr integer Buffer number
---@return table[] List of locations {file, line, col}
local function find_in_buffer(symbol, bufnr)
    local symbols = extract_symbols(bufnr, { symbol_name = symbol })

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

--- Find definitions in the current buffer
---@param symbol string The symbol to find
---@return table[] List of locations
function M.find_in_current_buffer(symbol) return find_in_buffer(symbol, 0) end

--- Check if a node is a function parameter with the given name
---@param func_node any Function definition node
---@param symbol string Symbol to look for
---@param bufnr integer Buffer number
---@return table? Location {file, line, col} or nil
local function find_in_function_params(func_node, symbol, bufnr)
    local params = func_node:field("parameters")
    if not params or #params == 0 then return nil end

    for _, param_list in ipairs(params) do
        for child in param_list:iter_children() do
            -- Parameters can be: identifier, parameter (with default), or ...
            local param_name = nil
            if child:type() == "identifier" then
                param_name = vim.treesitter.get_node_text(child, bufnr)
            elseif child:type() == "parameter" then
                local name_node = child:field("name")[1]
                if name_node then
                    param_name = vim.treesitter.get_node_text(name_node, bufnr)
                end
            end

            if param_name == symbol then
                local start_row, start_col = child:start()
                return {
                    file = vim.api.nvim_buf_get_name(bufnr),
                    line = start_row,
                    col = start_col,
                }
            end
        end
    end
    return nil
end

--- Find the closest definition in scope by walking up the tree
---@param symbol string The symbol to find
---@param bufnr integer Buffer number
---@param row integer Cursor row (0-indexed)
---@param col integer Cursor column (0-indexed)
---@return table? Location {file, line, col} or nil
local function find_in_scope(symbol, bufnr, row, col)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "r")
    if not ok or not parser then return nil end

    local tree = parser:parse()[1]
    if not tree then return nil end

    local node = tree:root():descendant_for_range(row, col, row, col)
    if not node then return nil end

    local query = require("r.lsp.queries").get("definitions")
    if not query then return nil end

    -- Walk up the tree to find containing scopes
    ---@type TSNode?
    local current = node
    while current do
        -- Check if we're inside a function - look for parameters first
        if current:type() == "function_definition" then
            local param_match = find_in_function_params(current, symbol, bufnr)
            if param_match then return param_match end

            -- Then check for local assignments within this function body
            local body = current:field("body")[1]
            if body then
                local body_matches = {}
                for id, match_node in query:iter_captures(body, bufnr) do
                    local capture_name = query.captures[id]
                    if capture_name == "name" or capture_name == "var_name" then
                        local text = vim.treesitter.get_node_text(match_node, bufnr)
                        if text == symbol then
                            local start_row, start_col = match_node:start()
                            -- Only consider assignments before the cursor
                            if
                                start_row < row or (start_row == row and start_col <= col)
                            then
                                table.insert(body_matches, {
                                    file = vim.api.nvim_buf_get_name(bufnr),
                                    line = start_row,
                                    col = start_col,
                                })
                            end
                        end
                    end
                end
                -- Return the closest match before cursor
                if #body_matches > 0 then
                    table.sort(body_matches, function(a, b)
                        if a.line ~= b.line then return a.line > b.line end
                        return a.col > b.col
                    end)
                    return body_matches[1]
                end
            end
        end

        current = current:parent()
    end

    -- No match in local scope, look for top-level file definitions only
    local file_matches = {}
    local root = tree:root()
    for id, match_node in query:iter_captures(root, bufnr) do
        local capture_name = query.captures[id]
        if capture_name == "name" or capture_name == "var_name" then
            local text = vim.treesitter.get_node_text(match_node, bufnr)
            if text == symbol then
                local start_row, start_col = match_node:start()
                -- Only consider definitions before the cursor
                if start_row < row or (start_row == row and start_col <= col) then
                    -- Check if this definition is at the top level (not inside a function)
                    local is_top_level = true
                    local parent = match_node:parent()
                    while parent do
                        if parent:type() == "function_definition" then
                            is_top_level = false
                            break
                        end
                        parent = parent:parent()
                    end

                    if is_top_level then
                        table.insert(file_matches, {
                            file = vim.api.nvim_buf_get_name(bufnr),
                            line = start_row,
                            col = start_col,
                        })
                    end
                end
            end
        end
    end

    -- Return the closest top-level match before cursor
    if #file_matches > 0 then
        table.sort(file_matches, function(a, b)
            if a.line ~= b.line then return a.line > b.line end
            return a.col > b.col
        end)
        return file_matches[1]
    end

    return nil
end

--- Parse an R file and extract all definitions
---@param filepath string Absolute path to the file
---@return table<string, table[]> Definitions map {symbol -> [{file, line, col}]}
local function parse_file_definitions(filepath)
    local definitions = {}

    local file = io.open(filepath, "r")
    if not file then return definitions end
    local content = file:read("*all")
    file:close()

    if not content or content == "" then return definitions end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
    vim.bo[bufnr].filetype = "r"

    local symbols = extract_symbols(bufnr)
    for _, sym in ipairs(symbols) do
        if not definitions[sym.name] then definitions[sym.name] = {} end
        table.insert(definitions[sym.name], {
            file = filepath, -- Use provided filepath, not the temp buffer name
            line = sym.name_start_row,
            col = sym.name_start_col,
        })
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
    return definitions
end

--- Recursively find R files in a directory
---@param dir string Directory path
---@param files table List to append files to
---@param max_depth? integer Maximum recursion depth (default 10)
---@param current_depth? integer Current depth
local function find_r_files(dir, files, max_depth, current_depth)
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
                find_r_files(full_path, files, max_depth, current_depth + 1)
            end
        elseif type == "file" then
            -- Match R source files
            if name:match("%.R$") or name:match("%.r$") then
                table.insert(files, full_path)
            end
        end
    end
end

--- Index all R files in the workspace
---@param force? boolean Force reindexing even if already done
function M.index_workspace(force)
    if indexed and not force then return end

    local cwd = vim.fn.getcwd()
    local files = {}
    find_r_files(cwd, files)

    workspace_index = {}
    file_mtimes = {}

    for _, filepath in ipairs(files) do
        local stat = vim.uv.fs_stat(filepath)
        if stat then
            file_mtimes[filepath] = stat.mtime.sec

            local definitions = parse_file_definitions(filepath)
            for symbol, locations in pairs(definitions) do
                if not workspace_index[symbol] then workspace_index[symbol] = {} end
                -- locations is now a list of {file, line, col}
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

    for symbol, locations in pairs(workspace_index) do
        workspace_index[symbol] = vim.tbl_filter(
            function(loc) return loc.file ~= filepath end,
            locations
        )
        if #workspace_index[symbol] == 0 then workspace_index[symbol] = nil end
    end

    file_mtimes[filepath] = stat.mtime.sec
    local definitions = parse_file_definitions(filepath)
    for symbol, locations in pairs(definitions) do
        if not workspace_index[symbol] then workspace_index[symbol] = {} end
        for _, loc in ipairs(locations) do
            table.insert(workspace_index[symbol], loc)
        end
    end
end

--- Find definition in workspace index
---@param symbol string The symbol to find
---@return table? Location or nil
function M.find_in_workspace(symbol)
    M.index_workspace()

    local locations = workspace_index[symbol]
    if locations and #locations > 0 then
        -- Return the first match (could be improved to handle multiple)
        return locations[1]
    end
    return nil
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

    -- 2. Check workspace index for other files
    M.index_workspace()
    local workspace_locations = workspace_index[symbol] or {}
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

--- Setup autocommand to update index on file save
function M.setup()
    vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = { "*.R", "*.r", "*.Rmd", "*.rmd", "*.qmd" },
        callback = function(ev) M.update_file_index(ev.file) end,
        desc = "Update R definition index on save",
    })
end

--- Rebuild the entire workspace index
-- TODO: This should be an autocommand so when a new file is added or modified outside
-- of Neovim, the index stays up to date
function M.rebuild_index()
    indexed = false
    M.index_workspace(true)
    vim.notify("R workspace index rebuilt", vim.log.levels.INFO)
end

--- Debug function to show workspace index state
function M.debug_index()
    M.index_workspace()
    local cwd = vim.fn.getcwd()
    local files = {}
    find_r_files(cwd, files)

    print("=== R.nvim Definition Index Debug ===")
    print("Working directory: " .. cwd)
    print("Files found: " .. #files)
    for _, f in ipairs(files) do
        print("  - " .. f)
    end
    print("Symbols indexed: " .. vim.tbl_count(workspace_index))
    for symbol, locations in pairs(workspace_index) do
        print("  " .. symbol .. " (" .. #locations .. " locations)")
        for _, loc in ipairs(locations) do
            print("    -> " .. loc.file .. ":" .. (loc.line + 1))
        end
    end
    print("======================================")
end

--- Extract document symbols from the current buffer
---@param bufnr integer Buffer number
---@return table[] List of DocumentSymbol objects
local function extract_document_symbols(bufnr)
    local symbols = extract_symbols(bufnr)

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
        require("r.lsp").send_msg({
            code = "Y",
            orig_id = req_id,
            symbols = symbols,
        })
    else
        require("r.lsp").send_msg({ code = "N" .. req_id })
    end
end

return M
