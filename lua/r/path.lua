local M = {}

-- Define the different types of paths.
local PathType = {
    FILE = "file",
    URL = "url",
    UNKNOWN = "unknown",
}

--- Checks if the function name is one of the path functions.
---@param function_name string The name of the function to check.
---@return boolean Returns true if the function name is a path function, otherwise false.
local function is_path_fun(function_name)
    local path_split_fun =
        { "here::here", "here", "file.path", "fs::path", "path", "paste0", "paste" }

    for _, value in ipairs(path_split_fun) do
        if function_name:match(value) then return true end
    end
    return false
end

--- Checks if the given path is a valid file path.
---@param path string The path to check.
---@return boolean Returns true if the path is a valid file path, otherwise false.
local function is_valid_file_path(path)
    local file_pattern = "^.*/[^/]+%.[^/]+$"
    return path:match(file_pattern) ~= nil
end

--- Checks if the given path is a valid directory path.
---@param path string The path to check.
---@return boolean Returns true if the path is a valid directory path, otherwise false.
local function is_valid_directory_path(path)
    local dir_pattern = "^.*/[^/]*[/]?$"
    return path:match(dir_pattern) ~= nil
end

--- Determines the type of path (file or url) based on the input string.
---@param str string The path string to be analyzed.
---@return string A string representing the type of path, which can be "file", "url", or "unknown".
local function get_path_type(str)
    -- Remove surrounding quotes if they exist
    local cleaned_str = str:match("^%s*['\"](.-)['\"]%s*$")
        or str:match("^%s*[(](.-)[)]%s*$")
        or str:match("^%s*(.-)%s*$")

    -- Check if the path starts with "whatever://"
    if cleaned_str:match("^[%w+-.]+://") then return PathType.URL end

    -- Check if the path starts with "/" or contains "/"
    if is_valid_file_path(cleaned_str) or is_valid_directory_path(cleaned_str) then
        return PathType.FILE
    end

    return PathType.UNKNOWN
end

--- Splits a path string into its components.
---@param file_path string The path string to be split.
---@return string A string representing the formatted path components, separated by commas.
local function split_path(file_path)
    local quote = file_path:match("^[\"']")
    if quote then file_path = file_path:sub(2, -2) end

    local components = {}
    local url_pattern = "^[a-zA-Z][a-zA-Z%d+-.]*://"

    if file_path:match(url_pattern) then
        local protocol, rest = file_path:match("^(.-://)(.+)")
        table.insert(components, protocol)
        local rest_pattern = "([^/]+)(/?)"
        for component, slash in rest:gmatch(rest_pattern) do
            if #component > 0 then table.insert(components, component .. slash) end
        end
    else
        local path_start = file_path:match("^/") and "/" or ""
        local path = path_start .. file_path:match("^/?(.+)")
        local is_first_component = true

        for component in path:gmatch("[^/]+") do
            if is_first_component then
                table.insert(components, path_start .. component)
                is_first_component = false
            else
                table.insert(components, component)
            end
        end
    end

    for i, component in ipairs(components) do
        components[i] = quote .. component .. quote
    end

    return table.concat(components, ", ")
end

--- Replaces the text of a node with a formatted path string.
---@param node table The Treesitter node to be updated.
---@param formatted_path string The formatted path string to replace the node's text with.
local function replace_path(node, formatted_path)
    local bufnr = vim.api.nvim_get_current_buf()
    local start_row, start_col, end_row, end_col = node:range()

    vim.api.nvim_buf_set_text(
        bufnr,
        start_row,
        start_col,
        end_row,
        end_col,
        { formatted_path }
    )
end

--- Processes and formats the path found in the current Treesitter node.
-- This function updates the path within the Treesitter node based on its type and context.
M.separate = function()
    local ts_utils = require("nvim-treesitter.ts_utils")
    local node = ts_utils.get_node_at_cursor()

    if not node or node:type() ~= "string_content" then return end

    local string_node = node:parent()
    if not string_node then return end

    local path = vim.treesitter.get_node_text(string_node, 0)

    local path_type = get_path_type(path)

    if path_type == PathType.UNKNOWN then return end

    local parent_node = string_node:parent()

    while parent_node do
        if parent_node:type() == "call" or parent_node:type() == "binary_operator" then
            break
        end
        parent_node = parent_node:parent()
    end

    if not parent_node then return end

    local function_name = vim.treesitter.get_node_text(parent_node:child(), 0)

    -- Do not process if the path is already surrounded by a path function
    if is_path_fun(function_name) and not (parent_node:type() == "binary_operator") then
        return
    end

    local formatted_path = split_path(path)

    if path_type == PathType.URL then
        formatted_path = "paste0(" .. formatted_path .. ")"
    else
        local config = require("r.config").get_config()
        local split_fun = config.path_split_fun
        formatted_path = split_fun .. "(" .. formatted_path .. ")"
    end

    replace_path(string_node, formatted_path)
end

return M
