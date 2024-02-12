local M = {}

--- Get the directory of the current buffer in Neovim.
-- This function retrieves the path of the current buffer and extracts the directory part.
---@return string The directory path of the current buffer or an empty string if not applicable.
function M.get_R_buffer_directory()
    local buffer_path = vim.api.nvim_buf_get_name(0)

    if buffer_path == "" then
        -- Buffer is not associated with a file.
        return ""
    end

    -- Extract the directory part of the path using Lua's string manipulation
    return buffer_path:match("^(.-)[\\/][^\\/]-$") or ""
end

--- Normalizes a file path by converting backslashes to forward slashes.
-- This function is particularly useful for ensuring file paths are compatible
-- with Windows systems, where backslashes are commonly used as path separators.
---@param path string The file path to normalize.
---@return string The normalized file path with all backslashes replaced by forward slashes.
function M.normalize_windows_path(path) return tostring(path:gsub("\\", "/")) end

--- Ensures that a given directory exists on the file system.
-- If the directory does not exist, it attempts to create it, including any
-- necessary parent directories. This function uses protected call (pcall) to
-- gracefully handle any errors that occur during directory creation, such as
-- permission issues.
---@param dir_path string The path of the directory to check or create.
---@return boolean Returns true if the directory exists or was successfully created.
-- Returns false if an error occurred during directory creation.
function M.ensure_directory_exists(dir_path)
    if vim.fn.isdirectory(dir_path) == 1 then return true end

    -- Using pcall to catch any errors during directory creation
    local status, err = pcall(function() vim.fn.mkdir(dir_path, "p") end)

    -- Check if pcall caught an error
    if not status then
        -- Log the error
        print("Error creating directory: " .. err)
        -- return false to indicate failure
        return false
    end

    -- Return true to indicate success
    return true
end

--- Check if a table has a specific string value
---@param value string
---@param tbl table
function M.value_in_table(value, tbl)
    for _, v in pairs(tbl) do
        if v == value then return true end
    end
    return false
end

return M
