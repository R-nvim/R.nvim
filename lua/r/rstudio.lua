local config = require("r.config").get_config()
local warn = require("r.log").warn
local M = {}

M.start = function()
    vim.g.R_Nvim_status = 6

    if config.is_windows then require("r.windows").set_R_home() end

    require("r.job").start("RStudio", { config.RStudio_cmd }, {
        on_stderr = require("r.job").on_stderr,
        on_exit = require("r.job").on_exit,
        detach = 1,
    })

    if config.is_windows then require("r.windows").unset_R_home() end

    require("r.run").wait_nvimcom_start()
end

--- Send coommand to RStudio
---@param command string
---@return boolean
M.send_cmd = function(command)
    if not require("r.job").is_running("RStudio") then
        warn("Is RStudio running?")
        return false
    end
    local cmd = command:gsub('"', '\\"')
    require("r.run").send_to_nvimcom("E", 'sendToConsole("' .. cmd .. '", execute=TRUE)')
    return true
end

return M
