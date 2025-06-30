local config = require("r.config").get_config()
local warn = require("r.log").warn

local r_pane = "?"
local ed_pane = "?"

local M = {}

M.start = function()
    if not vim.env.WEZTERM_PANE then
        warn(
            'external_term = "'
                .. config.external_term
                .. '" requires nvim running within WezTerm'
        )
        return
    end

    local term_cmd
    if config.external_term == "wezterm" then
        term_cmd = {
            "wezterm",
            "cli",
            "spawn",
            "--new-window",
            "--",
        }
    else
        ed_pane = vim.env.WEZTERM_PANE
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

        term_cmd = {
            "wezterm",
            "cli",
            "split-pane",
            location,
            "--percent",
            tostring(prcnt),
            "--",
        }
    end

    require("r.term").start(term_cmd, true)
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

--- Set number of Wezterm pane where R is running
---@param p string
M.set_r_pane = function(p) r_pane = p end

--- Get number of Wezterm pane where R is running
---@return string
M.get_r_pane = function() return r_pane end

--- Get number of Neovim pane
---@return string
M.get_editor_pane = function() return ed_pane end

return M
