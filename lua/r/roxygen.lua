local warn = require("r.log").warn
local M = {}

local parsers = require("nvim-treesitter.parsers")
local api = vim.api
local treesitter = vim.treesitter

--- Checks if there is a roxygen comment above the given line.
---@param start_line number: The line number to start checking from.
---@return boolean: True if a roxygen comment is found, false otherwise.
local function has_roxygen(start_line)
    local lines_above = api.nvim_buf_get_lines(0, 0, start_line, false)

    for i = #lines_above, 1, -1 do
        local line = lines_above[i]
        if not line:match("^%s*$") then return line:match("^%s*#'%s*") ~= nil end
    end

    return false
end

--- Inserts a roxygen comment template above the function at the current cursor position.
---@param bufnr number: The buffer number where the function is located. If nil, uses the current buffer.
M.insert_roxygen = function(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()

    if vim.bo[bufnr].filetype ~= "r" then
        warn("This function is only available for R files.")
        return
    end

    local lang = parsers.get_buf_lang(bufnr)
    if not lang then
        warn("Could not determine the language of the buffer.")
        return
    end

    local parser = parsers.get_parser(bufnr)
    if not parser then
        warn("No parser found for the current buffer.")
        return
    end

    local query = [[
        (function_definition) @function
    ]]
    local query_obj = treesitter.query.parse(lang, query)
    local root = parser:parse()[1]:root()

    local cursor_pos = api.nvim_win_get_cursor(0)
    local cursor_line = cursor_pos[1] - 1

    local roxygen_template = {
        "#' Title",
        "#'",
    }

    for _, function_node in query_obj:iter_captures(root, bufnr) do
        local start_row, _, end_row, _ = function_node:range()

        -- The cursor is within the range of a function definition
        if cursor_line >= start_row and cursor_line <= end_row then
            if has_roxygen(start_row) then
                warn("Roxygen comment already exists for this function.")
                return
            end

            local parameters = function_node:child(1)
            if not parameters then return end

            for parameter in parameters:iter_children() do
                if parameter:type() == "parameter" then
                    local name_node = parameter:field("name")
                    if name_node then
                        local name_value = treesitter.get_node_text(name_node[1], bufnr)
                        table.insert(
                            roxygen_template,
                            string.format("#' @param %s", name_value)
                        )
                    end
                end
            end

            table.insert(roxygen_template, "#'")
            table.insert(roxygen_template, "#' @return")
            table.insert(roxygen_template, "#' @export")

            api.nvim_buf_set_lines(bufnr, start_row, start_row, false, roxygen_template)
            return
        end
    end

    warn("No function found at the current cursor position.")
end

return M
