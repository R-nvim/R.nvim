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
M.start = function(term_cmd)
    vim.g.R_Nvim_status = 6
    if config.silent_term then
        vim.system(term_cmd, { text = true }, on_exit)
    else
        local initterm = {
            'cd "' .. vim.fn.getcwd() .. '"',
            table.concat(term_cmd, " "),
        }
        local init_file = config.tmpdir .. "/initterm_" .. vim.fn.rand() .. ".sh"
        vim.fn.writefile(initterm, init_file)
        local job = require("r.job")
        job.start("Terminal emulator", { "sh", init_file }, {
            on_stderr = job.on_stderr,
            on_exit = job.on_exit,
            detach = 1,
        })
        require("r.edit").add_for_deletion(init_file)
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
