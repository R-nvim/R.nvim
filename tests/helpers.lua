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


return M
