local config = require("r.config").get_config()
local utils = require("r.utils")
local warn = require("r").warn
local saved_home = nil
local M = {}

M.set_R_home = function()
    -- R and Vim use different values for the $HOME variable.
    if config.set_home_env then
        saved_home = vim.env.HOME
        local obj = utils.system({
            "reg.exe",
            "QUERY",
            "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders",
            "/v",
            "Personal",
        }, { text = true }):wait()
        local prs = obj.stdout
        if prs and #prs > 0 then
            prs = prs:gsub(".*REG_SZ%s*", "")
            prs = prs:gsub("\n", "")
            prs = prs:gsub("\r", "")
            prs = prs:gsub("%s*$", "")
            vim.env.HOME = prs
        end
    end
end

M.unset_R_home = function()
    if saved_home then
        vim.env.HOME = saved_home
        saved_home = nil
    end
end

M.start_Rgui = function()
    vim.g.R_Nvim_status = 6

    if vim.fn.match(config.R_app, "Rterm") then
        warn('"R_app" cannot be "Rterm.exe". R will crash if you send any command.')
        vim.wait(200)
    end

    M.set_R_home()
    vim.fn.system("start " .. config.R_app .. " " .. table.concat(config.R_args, " "))
    M.unset_R_home()

    require("r.run").wait_nvimcom_start()
end

-- Called by rnvimserver
M.clean_and_start_Rgui = function()
    require("r.run").clear_R_info()
    M.start_Rgui()
end

M.send_cmd_to_Rgui = function(command)
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
