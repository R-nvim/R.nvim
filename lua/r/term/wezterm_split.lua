local config = require("r.config").get_config()
local warn = require("r.log").warn

local r_pane = "?"

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
        config.R_app,
    }

    local rargs = require("r.run").get_r_args()
    if rargs ~= "" then
        local argsls = vim.fn.split(rargs, " ")
        for _, v in pairs(argsls) do
            table.insert(term_cmd, v)
        end
    end

    require("r.term").start(term_cmd)
end

--- Send line of command to R Console
---@param command string
---@return boolean
M.send_cmd = function(command)
    local cmd = require("r.term").sanitize(command, true)
    local scmd =
        { "wezterm", "cli", "send-text", "--no-paste", "--pane-id", r_pane, cmd .. "\n" }
    local res = require("r.term").send(scmd)
    return res
end

--- Set the window id of Kitty window where R is running
---@param p string
M.set_r_pane = function(p) r_pane = p end

return M
