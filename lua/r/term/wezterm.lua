local config = require("r.config").get_config()
local warn = require("r.log").warn

local r_pane = "1"

local M = {}

M.start = function()
    if not vim.env.WEZTERM_PANE then
        warn('external_term = "wezterm" requires nvim running within WezTerm')
        return
    end

    local term_cmd = {
        "wezterm",
        "cli",
        "spawn",
        "--new-window",
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

--- Set pane number of Wezterm window where R is running
---@param p string
M.set_r_pane = function(p) r_pane = p end

return M
