local warn = require("r.log").warn
local M = {}

--- Checks if there is a roxygen comment above the given line.
---@param start_line number: The line number to start checking from.
---@return boolean: True if a roxygen comment is found, false otherwise.
local function has_roxygen(start_line)
    local lines_above = vim.api.nvim_buf_get_lines(0, 0, start_line, false)

    for i = #lines_above, 1, -1 do
        local line = lines_above[i]
        if not line:match("^%s*$") then return line:match("^%s*#'%s*") ~= nil end
    end

    return false
end

--- Inserts a roxygen comment template above the function at the current cursor position.
---@param bufnr number: The buffer number where the function is located. If nil, uses the current buffer.
M.insert_roxygen = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    if vim.bo[bufnr].filetype ~= "r" then
        warn("This function is only available for R files.")
        return
    end

    local parser = vim.treesitter.get_parser(bufnr, "r")
    if not parser then return end
    local tree = parser:parse()[1]
    local root = tree:root()

    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    if not cursor_pos then return end
    local cursor_line = cursor_pos[1] - 1

    local query = vim.treesitter.query.parse(
        "r",
        [[
        (function_definition) @function
    ]]
    )

    for _, function_node in query:iter_captures(root, bufnr) do
        local start_row, _, end_row, _ = function_node:range()

        if cursor_line >= start_row and cursor_line <= end_row then
            if has_roxygen(start_row) then
                warn("Roxygen comment already exists for this function.")
                return
            end

            local roxygen_template = {
                "#' Title",
                "#'",
            }

            local parameters = function_node:child(1)
            if parameters then
                for parameter in parameters:iter_children() do
                    if parameter:type() == "parameter" then
                        local name_node = parameter:field("name")
                        if name_node then
                            local name_value =
                                vim.treesitter.get_node_text(name_node[1], bufnr)
                            table.insert(
                                roxygen_template,
                                string.format("#' @param %s", name_value)
                            )
                        end
                    end
                end
            end

            table.insert(roxygen_template, "#'")
            table.insert(roxygen_template, "#' @return")
            table.insert(roxygen_template, "#' @export")

            vim.api.nvim_buf_set_lines(
                bufnr,
                start_row,
                start_row,
                false,
                roxygen_template
            )
            return
        end
    end

    warn("No function found at the current cursor position.")
end

-- Temporary highlighting of ROxygen comments while waiting for native
-- tree-sitter-r support.
local ons = vim.api.nvim_create_namespace("ROxygenNS")
M.hl = function()
    -- From Vim syntax/r.vim
    local rotags = {
        "S3method",
        "aliases",
        "author",
        "backref",
        "concept",
        "describeIn",
        "description",
        "details",
        "docType",
        "encoding",
        "eval",
        "evalRd",
        "example",
        "examples",
        "export",
        "exportClass",
        "exportMethod",
        "exportPattern",
        "family",
        "field",
        "format",
        "import",
        "importClassesFrom",
        "importFrom",
        "importMethodsFrom",
        "include",
        "includeRmd",
        "inherit",
        "inheritDotParams",
        "inheritParams",
        "inheritSection",
        "keywords",
        "md",
        "method",
        "name",
        "noMd",
        "noRd",
        "note",
        "order",
        "param",
        "rawNamespace",
        "rawRd",
        "rdname",
        "references",
        "return",
        "section",
        "seealso",
        "slot",
        "source",
        "template",
        "templateVar",
        "title",
        "usage",
        "useDynLib",
    }
    vim.api.nvim_buf_clear_namespace(0, ons, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    local empty_prv_line = true

    local nlines = #lines
    local k = 1
    while k <= nlines do
        local v = lines[k]
        if
            empty_prv_line
            and v:find("^%s*#' ")
            and not v:find("^%s*#'%s+@[a-zA-Z0-9]")
        then
            local o = { end_row = k - 1, end_col = string.len(v), hl_group = "Title" }
            local i = v:find("'")
            vim.api.nvim_buf_set_extmark(0, ons, k - 1, i + 1, o)
        end
        empty_prv_line = v:find("^%s*$") and true or false

        if v:find("^%s*#'%s+@[a-zA-Z0-9]") then
            local i, j = v:find("@[a-zA-Z0-9]*")
            if i then
                local tag = v:match("^%s*#'%s+@([a-zA-Z0-9]*)")
                local hlg = "Error"
                for _, v2 in pairs(rotags) do
                    if tag == v2 then
                        hlg = "Keyword"
                        if tag == "param" or tag == "importFrom" then
                            local m, n = v:find("[a-zA-Z0-9_%.\\]+", j + 1)
                            if m and n then
                                vim.api.nvim_buf_set_extmark(0, ons, k - 1, m - 1, {
                                    end_row = k - 1,
                                    end_col = n,
                                    hl_group = "Variable",
                                })
                            end
                        end
                        break
                    end
                end
                vim.api.nvim_buf_set_extmark(0, ons, k - 1, i - 1, {
                    end_row = k - 1,
                    end_col = j,
                    hl_group = hlg,
                })
                if tag == "examples" then
                    k = k + 1
                    while k <= nlines do
                        v = lines[k]
                        if v:find("^%s*#'%s+@") or not v:find("^%s*#'") then
                            k = k - 1
                            break
                        end
                        if string.len(v) > 3 then
                            local o = {
                                end_row = k - 1,
                                end_col = string.len(v),
                                hl_group = "SpecialComment",
                            }
                            vim.api.nvim_buf_set_extmark(0, ons, k - 1, 3, o)
                        end
                        k = k + 1
                    end
                end
            end
        end
        k = k + 1
    end
end

return M
