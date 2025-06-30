local config = require("r.config").get_config()
local warn = require("r.log").warn

local r_wid = "2"

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
    if not vim.env.KITTY_WINDOW_ID then
        warn('external_term = "kitty_split" requires nvim running within Kitty')
        return
    end

    local location = "vsplit"

    local nw = vim.o.number and vim.o.numberwidth or 0
    local swd = config.rconsole_width + config.min_editor_width + 1 + nw
    if config.rconsole_width == 0 or (vim.fn.winwidth(0) < swd) then
        location = "hsplit"
    end

    local bias = 50
    if location == "vsplit" then
        bias = vim.fn.round(100 * config.rconsole_width / vim.fn.winwidth(0))
    else
        bias = vim.fn.round(100 * config.rconsole_height / vim.fn.winheight(0))
    end
    if bias > 80 then bias = 80 end

    local term_cmd = {
        "kitten",
        "@",
        "launch",
        "--type=window",
        "--location=" .. location,
        "--bias=" .. tostring(bias),
        "--keep-focus",
        "--cwd=current",
        "--env",
        "RNVIM_TMPDIR=" .. config.tmpdir:gsub(" ", "\\ "),
        "--env",
        "RNVIM_COMPLDIR=" .. config.compldir:gsub(" ", "\\ "),
        "--env",
        "RNVIM_ID=" .. vim.env.RNVIM_ID,
        "--env",
        "RNVIM_SECRET=" .. vim.env.RNVIM_SECRET,
        "--env",
        "RNVIM_PORT=" .. vim.env.RNVIM_PORT,
        "--env",
        "R_DEFAULT_PACKAGES=" .. vim.env.R_DEFAULT_PACKAGES,
    }

    local rargs = require("r.run").get_r_args()
    if rargs == "" then
        table.insert(term_cmd, config.R_app)
    else
        local rcmd = config.R_app .. " " .. rargs
        local rcmdls = vim.fn.split(rcmd, " ")
        for _, v in pairs(rcmdls) do
            table.insert(term_cmd, v)
        end
    end

    vim.notify(location)

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
    cmd = cmd:gsub("\\", "\\\\")

    local scmd = { "kitten", "@", "send-text", "-m", "id:" .. r_wid, cmd .. "\n" }
    local obj = vim.system(scmd):wait()
    if obj.code ~= 0 then
        warn(obj.stderr)
        require("r.run").clear_R_info()
        return false
    end

    return true
end

--- Set the window id of Kitty window where R is running
---@param i string
M.set_r_wid = function(i) r_wid = i end

return M
