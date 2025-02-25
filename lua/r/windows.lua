local config = require("r.config").get_config()
local saved_home = nil
local M = {}

M.set_R_home = function()
    -- R and Vim use different values for the $HOME variable.
    if config.set_home_env then
        saved_home = vim.env.HOME
        local obj = vim.system({
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

return M
