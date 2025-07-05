local config = require("r.config").get_config()
local warn = require("r.log").warn

local r_wid = "2"

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

    require("r.term").start(term_cmd)
end

--- Send line of command to R Console
---@param command string
---@return boolean
M.send_cmd = function(command)
    local cmd = require("r.term").sanitize(command, true)
    cmd = cmd:gsub("\\", "\\\\")

    local scmd = { "kitten", "@", "send-text", "-m", "id:" .. r_wid, cmd .. "\n" }

    local res = require("r.term").send(scmd)
    return res
end

--- Set the window id of Kitty window where R is running
---@param i string
M.set_r_wid = function(i) r_wid = i end

return M
