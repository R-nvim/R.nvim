local config = require("r.config").get_config()
local warn = require("r.log").warn

local M = {}

M.start = function()
    vim.g.R_Nvim_status = 6

    if config.R_app:find("Rterm") then
        warn('"R_app" cannot be "Rterm.exe". R will crash if you send any command.')
        vim.wait(200)
    end

    M.set_R_home()
    vim.fn.system("start " .. config.R_app .. " " .. require("r.run").get_r_args())
    M.unset_R_home()

    require("r.run").wait_nvimcom_start()
end

-- Called by rnvimserver
M.clean_and_start = function()
    require("r.run").clear_R_info()
    M.start()
end

---Send command to Rgui.exe
---@param command string
---@return boolean
M.send_cmd = function(command)
    local cmd
    if config.clear_line then
        cmd = "\001" .. "\013" .. command .. "\n"
    else
        cmd = command .. "\n"
    end
    require("r.job").stdin("Server", "83" .. cmd)
    return true
end

return M
