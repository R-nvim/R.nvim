local config = require("r.config").get_config()
local warn = require("r.log").warn
local r_pane = "?"

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

M.start = function()
    if not vim.env.WEZTERM_PANE then
        warn('external_term = "wezterm_split" requires nvim running within WezTerm')
        return
    end

    local location = "--right"
    local nw = vim.o.number and vim.o.numberwidth or 0
    local swd = config.rconsole_width + config.min_editor_width + 1 + nw
    if config.rconsole_width == 0 or (vim.fn.winwidth(0) < swd) then
        location = "--bottom"
    end

    local prcnt
    if location == "--right" then
        prcnt = vim.fn.round(100 * config.rconsole_width / vim.fn.winwidth(0))
    else
        prcnt = vim.fn.round(100 * config.rconsole_height / vim.fn.winheight(0))
    end
    if prcnt > 80 then prcnt = 80 end
    if prcnt < 5 then prcnt = 5 end

    --- external_term = 'wezterm cli split-pane --bottom --percent 30  -- ',
    local term_cmd = {
        "wezterm",
        "cli",
        "split-pane",
        location,
        "--percent",
        tostring(prcnt),
        "--",
        config.R_app
    }

    local rargs = require("r.run").get_r_args()
    if rargs ~= "" then
        local argsls = vim.fn.split(rargs, " ")
        for _, v in pairs(argsls) do
            table.insert(term_cmd, v)
        end
    end

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

--- Send line of command to R Console
---@param command string
---@return boolean
M.send_cmd = function(command)
    local cmd = command

    if config.clear_line then
        if config.editing_mode == "emacs" then
            cmd = "\001\011" .. cmd
        else
            cmd = "\0270Da" .. cmd
        end
    end

    -- Send the command to R running in an external terminal emulator
    if cmd:find("^-") then cmd = " " .. cmd end

    local scmd = { "wezterm", "cli", "send-text", "--no-paste", "--pane-id", r_pane, cmd .. "\n" }
    local obj = vim.system(scmd):wait()
    if obj.code ~= 0 then
        warn(obj.stderr)
        require("r.run").clear_R_info()
        return false
    end

    return true
end

--- Set the window id of Kitty window where R is running
---@param p string
M.set_r_pane = function(p) r_pane = p end

return M
