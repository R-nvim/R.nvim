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

local get_fw_info_X = function()
    local config = require("r.config").get_config()
    local warn = require("r").warn
    local obj = vim.system({ "xprop", "-root" }, { text = true }):wait()
    if obj.code ~= 0 then
        warn("Failed to run `xprop -root`")
        return
    end
    local xroot = vim.split(obj.stdout, "\n")
    local awin = nil
    for _, v in pairs(xroot) do
        if v:find("_NET_ACTIVE_WINDOW%(WINDOW%): window id # ") then
            awin = v:gsub("_NET_ACTIVE_WINDOW%(WINDOW%): window id # ", "")
            break
        end
    end
    if not awin then
        warn("Failed to get ID of active window")
        return
    end
    obj = vim.system({ "xprop", "-id", awin }, { text = true }):wait()
    if obj.code ~= 0 then
        warn("xprop is required to get window PID")
        return
    end
    local awinf = vim.split(obj.stdout, "\n")
    local pid = nil
    local nm = nil
    for _, v in pairs(awinf) do
        if v:find("_NET_WM_PID%(CARDINAL%) = ") then
            pid = v:gsub("_NET_WM_PID%(CARDINAL%) = ", "")
        end
        if v:find("WM_NAME%(STRING%) = ") then
            nm = v:gsub("WM_NAME%(STRING%) = ", "")
            nm = nm:gsub('"', "")
        end
    end
    if not pid or not nm then
        warn(
            "Failed to PID or name of active window ("
                .. awin
                .. "): "
                .. tostring(pid)
                .. " "
                .. tostring(nm)
        )
        return
    end
    config.term_title = nm
    config.term_pid = tonumber(pid)
end

local get_fw_info_Sway = function()
    local config = require("r.config").get_config()
    local obj = vim.system({ "swaymsg", "-t", "get_tree" }, { text = true }):wait()
    local t = vim.json.decode(obj.stdout, { luanil = { object = true, array = true } })
    for _, v1 in pairs(t.nodes) do
        if #v1 and v1.type == "output" and v1.nodes then
            for _, v2 in pairs(v1.nodes) do
                if #v2 and v2.type == "workspace" and v2.nodes then
                    for _, v3 in pairs(v2.nodes) do
                        if v3.focused == true then
                            config.term_title = v3.name
                            config.term_pid = v3.pid
                        end
                    end
                end
            end
        end
    end
end

--- Get PID and name of active window and register them in config.term_pid and
--- config.term_title respectively.
--- This function call the appropriate function for each system.
function M.get_focused_win_info()
    local config = require("r.config").get_config()
    local warn = require("r").warn
    if config.has_X_tools then
        get_fw_info_X()
    elseif
        vim.env.XDG_CURRENT_DESKTOP == "sway" or vim.env.XDG_SESSION_DESKTOP == "sway"
    then
        get_fw_info_Sway()
    else
        warn(
            "Cannot get active window info on your system.\n"
                .. "Please, do a pull request fixing the problem.\n"
                .. "See: R.nvim/lua/r/utils.lua"
        )
    end
end

return M
