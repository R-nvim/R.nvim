local config = require("r.config").get_config()
local warn = require("r.log").warn

local on_exit = function(obj)
    if obj.code ~= 0 then
        warn(
            "Terminal emulator exit code: "
                .. tostring(obj.code)
                .. "\nstdout: "
                .. obj.stdout
                .. "\nstderr: "
                .. obj.stderr
        )
    end
end

local M = {}

--- Prepare string to be sent to terminal
---@param cmd string The command to be sent
---@param hyphen boolean Should avoid hypen at the beginning?
---@return string
M.sanitize = function(cmd, hyphen)
    if config.clear_line then
        if config.editing_mode == "emacs" then
            cmd = "\001\011" .. cmd
        else
            cmd = "\0270Da" .. cmd
        end
    end

    -- Send the command to R running in an external terminal emulator
    if hyphen then
        if cmd:find("^-") then cmd = " " .. cmd end
    end
    return cmd
end

--- Start terminal emulator running R
---@param term_cmd table The command to execute.
---@param add_rargs boolean Add R_app and args to command?
M.start = function(term_cmd, add_rargs)
    vim.g.R_Nvim_status = 6

    if add_rargs then
        table.insert(term_cmd, config.R_app)
        local rargs = require("r.run").get_r_args()
        if rargs ~= "" then
            local argsls = vim.fn.split(rargs, " ")
            for _, v in pairs(argsls) do
                table.insert(term_cmd, v)
            end
        end
    end

    if config.silent_term then
        vim.system(term_cmd, { text = true }, on_exit)
    else
        local job = require("r.job")
        job.start("Terminal emulator", term_cmd, {
            on_stderr = job.on_stderr,
            on_exit = job.on_exit,
            detach = true,
        })
    end
    require("r.run").wait_nvimcom_start()
end

--- Send command to terminal
---@param cmd table The complete command to execute.
---@return boolean
M.send = function(cmd)
    local obj = vim.system(cmd):wait()
    if obj.code ~= 0 then
        warn(obj.stderr)
        require("r.run").clear_R_info()
        return false
    end
    return true
end

return M
