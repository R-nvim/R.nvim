local M = {}

---Function to write data to a file
---@param filepath string: Path to the file
---@param data string: Data to be written to the file
---@param mode string: "w" for overwrite, "a" for append
---@return boolean success: Boolean indicating if the operation was successful
---@return string Msg: Error message if the operation failed, filepath if it was successful
function M.write_to_file(filepath, data, mode)
    local file, errMsg = io.open(filepath, mode)
    if not file then
        ---@diagnostic disable-next-line: return-type-mismatch
        return false, errMsg
    end

    ---@diagnostic disable-next-line: redefined-local
    local success, errMsg = file:write(data)
    if not success then
        ---@diagnostic disable-next-line: return-type-mismatch
        return false, errMsg
    end

    file:close()
    return true, filepath
end

--- Function to mock cursor position in a new neovim process.
-- This Function is intended to be used in tests.
-- it:
-- [1] creates a temporary file
-- [2] overwrites it with the specified content
-- [3] spawns a new neovim process with it as buffer
-- [4] moves the cursor to the specified line and column
--- @param content string
--- @param cursor_position table
--- @return file*?
--- @return string?
function M.mock_cursor_position(content, cursor_position)
    local filepath = os.tmpname()
    M.write_to_file(filepath, content, "w")
    local nvim_bin = "/usr/bin/nvim" -- FIXME: for non-Linux
    local command = string.format(
        "%s --noplugin -c 'lua vim.fn.cursor(%s,%s)' %s",
        nvim_bin,
        cursor_position[1],
        cursor_position[2],
        filepath
    )
    local handle, err = io.popen(command, "r")
    if handle then
        local _ = handle:read("*a")
        return handle, filepath -- for cleanup after testing
    else
        --TODO: handle err
        print(err)
        return nil
    end
end

--- Function to run commands in sequence in a new neovim process.
-- This function 
-- [1] Opens file at "filepath"
-- [2] Runs commands
-- [3] Closes the file
-- [4] Returns the output of the commands
---@param filepath string 
---@param commands table 
---@return any output 
function M.run_commands(filepath, commands)
    local nvim_bin = "/usr/bin/nvim" -- FIXME: for non-Linux
    local command = string.format(
        "%s --noplugin -c 'lua %s' %s",
        nvim_bin,
        table.concat(commands, ";\n"),
        filepath
    )
    local handle, err = io.popen(command, "r")
    if handle then
        local output = handle:read("*a")
        handle:close()
        return output
    else
        print(err)
        return output 
    end
end

return M
