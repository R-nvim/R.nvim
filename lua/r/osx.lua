local config = require("r.config").get_config()
local warn = require("r").warn
local R64app = nil

local M = {}

M.start_Rapp = function()
    vim.g.R_Nvim_status = 6

    if not R64app then R64app = vim.fn.isdirectory("/Applications/R64.app") == 1 end

    local rcmd = R64app and "/Applications/R64.app" or "/Applications/R.app"

    local args_str = table.concat(config.R_args, " ")
    if args_str ~= " " and args_str ~= "" then
        -- https://github.com/jcfaria/Vim-R-plugin/issues/63
        -- https://stat.ethz.ch/pipermail/r-sig-mac/2013-February/009978.html
        warn(
            'R.app does not support command line arguments. To pass "'
                .. args_str
                .. '" to R, you must put "applescript = 0" in your config to run R in a terminal emulator.'
        )
    end
    local rlog = vim.fn.system("open " .. rcmd)
    if vim.v.shell_error ~= 0 then warn(rlog) end
    require("r.run").wait_nvimcom_start()
end

M.send_cmd_to_Rapp = function(command, _)
    local cmd = config.clear_line and "\001\013" .. command or command

    local rcmd = R64app and "R64" or "R"

    -- For some reason, it doesn't like "\025"
    cmd = cmd:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("'", "'\\\\''")
    vim.fn.system(
        "osascript -e 'tell application \"" .. rcmd .. '" to cmd "' .. cmd .. "\"'"
    )
    return 1
end

return M
