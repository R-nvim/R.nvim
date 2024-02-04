local config = require("r.config").get_config()
local warn = require("r").warn
local M = {}

M.start_RStudio = function()
    if vim.g.R_Nvim_status == 5 then return end
    vim.g.R_Nvim_status = 4

    if vim.fn.has("win32") ~= 0 then require("r.windows").set_R_home() end

    require("r.job").start("RStudio", { config.RStudio_cmd }, {
        on_stderr = require("r.job").on_stderr,
        on_exit = require("r.job").on_exit,
        detach = 1,
    })

    if vim.fn.has("win32") ~= 0 then require("r.windows").unset_R_home() end

    require("r.run").wait_nvimcom_start()
end

M.send_cmd_to_RStudio = function(command, _)
    if not require("r.job").is_running("RStudio") then
        warn("Is RStudio running?")
        return 0
    end

    local cmd = vim.fn.substitute(command, '"', '\\"', "g")
    require("r.run").send_to_nvimcom("E", 'sendToConsole("' .. cmd .. '", execute=TRUE)')
    return 1
end

return M
