--- LSP Goto Definition support for R.nvim
--- Provides textDocument/definition functionality with workspace-wide search
--- and package source resolution (similar to R languageserver behavior)

local M = {}

local warn = require("r.log").warn

--- Cache for workspace definitions: { symbol_name -> [{file, line, col}] }
---@type table<string, table[]>
local workspace_index = {}

--- File modification times for cache invalidation
---@type table<string, number>
local file_mtimes = {}

--- Whether initial indexing has been done
local indexed = false

--- Tree-sitter query for finding function definitions
--- Matches patterns like: fn_name <- function(...) or fn_name = function(...)
local definition_query_str = [[
    ; Function assignments with <- operator
    (binary_operator
        lhs: (identifier) @name
        operator: "<-"
        rhs: (function_definition)) @definition

    ; Function assignments with <<- operator
    (binary_operator
        lhs: (identifier) @name
        operator: "<<-"
        rhs: (function_definition)) @definition

    ; Function assignments with = operator
    (binary_operator
        lhs: (identifier) @name
        operator: "="
        rhs: (function_definition)) @definition

    ; Variable assignments with <- (non-function)
    (binary_operator
        lhs: (identifier) @var_name
        operator: "<-"
        rhs: (_) @var_value) @var_definition

    ; Variable assignments with = (non-function)
    (binary_operator
        lhs: (identifier) @var_name
        operator: "="
        rhs: (_) @var_value) @var_definition
]]

--- Cached parsed query
---@type vim.treesitter.Query?
local definition_query = nil

--- Get or create the definition query
---@return vim.treesitter.Query?
local function get_query()
    if definition_query then return definition_query end
    local ok, query = pcall(vim.treesitter.query.parse, "r", definition_query_str)
    if ok then
        definition_query = query
        return query
    end
    warn("Failed to parse tree-sitter query for definitions")
    return nil
end

--- Find definitions in a buffer using tree-sitter
---@param symbol string The symbol to find
---@param bufnr integer Buffer number
---@return table[] List of locations {file, line, col}
local function find_in_buffer(symbol, bufnr)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "r")
    if not ok or not parser then return {} end

    local tree = parser:parse()[1]
    if not tree then return {} end

    local root = tree:root()
    local query = get_query()
    if not query then return {} end

    local matches = {}
    local seen = {}

    for id, node in query:iter_captures(root, bufnr) do
        local capture_name = query.captures[id]
        if capture_name == "name" or capture_name == "var_name" then
            local text = vim.treesitter.get_node_text(node, bufnr)
            if text == symbol then
                local start_row, start_col = node:start()
                local file = vim.api.nvim_buf_get_name(bufnr)

                -- Create unique key to avoid duplicates from overlapping patterns
                local key = string.format("%s:%d:%d", file, start_row, start_col)
                if not seen[key] then
                    seen[key] = true
                    table.insert(matches, {
                        file = file,
                        line = start_row, -- 0-indexed
                        col = start_col, -- 0-indexed
                    })
                end
            end
        end
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

    -- Get the node at cursor position
    local node = tree:root():descendant_for_range(row, col, row, col)
    if not node then return nil end

    local query = get_query()
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

    -- Read file content
    local file = io.open(filepath, "r")
    if not file then return definitions end
    local content = file:read("*all")
    file:close()

    if not content or content == "" then return definitions end

    -- Create a temporary buffer for parsing
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
    vim.bo[bufnr].filetype = "r"

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "r")
    if ok and parser then
        local tree = parser:parse()[1]
        if tree then
            local root = tree:root()
            local query = get_query()
            if query then
                -- Track seen locations to avoid duplicates from overlapping patterns
                local seen = {}
                for id, node in query:iter_captures(root, bufnr) do
                    local capture_name = query.captures[id]
                    if capture_name == "name" or capture_name == "var_name" then
                        local text = vim.treesitter.get_node_text(node, bufnr)
                        local start_row, start_col = node:start()

                        -- Create unique key for this location
                        local key = string.format("%s:%d:%d", text, start_row, start_col)
                        if not seen[key] then
                            seen[key] = true
                            if not definitions[text] then definitions[text] = {} end
                            table.insert(definitions[text], {
                                file = filepath,
                                line = start_row,
                                col = start_col,
                            })
                        end
                    end
                end
            end
        end
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

    -- Remove old entries for this file
    for symbol, locations in pairs(workspace_index) do
        workspace_index[symbol] = vim.tbl_filter(
            function(loc) return loc.file ~= filepath end,
            locations
        )
        if #workspace_index[symbol] == 0 then workspace_index[symbol] = nil end
    end

    -- Add new entries
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
        -- Response is async, so return here
        return
    end

    -- No definition found
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

return M
