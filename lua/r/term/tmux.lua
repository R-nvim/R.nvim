local config = require("r.config").get_config()
local uv = vim.uv
local warn = require("r.log").warn

local r_pane = "?"
local term_name = nil
local term_cmd = {}
local tmuxsname = nil
local is_tmux_split = false

local external_term_config = function()
    tmuxsname = "Rnvim-" .. tostring(vim.fn.localtime()):gsub(".*(...)", "%1")

    if config.external_term ~= "" and config.external_term ~= "default" then
        -- User defined terminal
        term_name = config.external_term:gsub(" .*", "")
        if vim.fn.executable(term_name) == 0 then
            warn(
                "'"
                    .. term_name
                    .. "' is not executable. Please, check the value of `external_term`."
            )
            return
        end
        if config.external_term:find(" ") then
            -- Complete command defined by the user
            term_cmd = vim.fn.split(config.external_term, " ")
            return
        end
    end

    local etime = uv.hrtime()
    if config.external_term == "default" and not config.is_windows then
        -- Terminal name not defined. Try to find a known one.
        local terminals = {
            "gnome-terminal",
            "konsole",
            "xfce4-terminal",
            "alacritty",
            "xterm",
        }
        if vim.env.WAYLAND_DISPLAY then table.insert(terminals, 1, "foot") end

        for _, term in pairs(terminals) do
            if vim.fn.executable(term) == 1 then
                term_name = term
                break
            end
        end
    end

    if not term_name then
        warn(
            "Please, set the value of `external_term` as either the name of your terminal emulator executable or the complete command to run it."
        )
        return
    end

    term_cmd = { term_name }

    if
        vim.tbl_contains(
            { "foot", "gnome-terminal", "xfce4-terminal", "alacritty" },
            term_name
        )
    then
        table.insert(term_cmd, "--title")
        table.insert(term_cmd, "R")
    elseif vim.tbl_contains({ "xterm", "uxterm", "lxterm" }, term_name) then
        table.insert(term_cmd, "-title")
        table.insert(term_cmd, "R")
    end

    if term_name == "foot" then
        table.insert(term_cmd, "--log-level")
        table.insert(term_cmd, "error")
    end

    if term_name == "gnome-terminal" then
        table.insert(term_cmd, "--")
    elseif vim.tbl_contains({ "terminator", "xfce4-terminal" }, term_name) then
        table.insert(term_cmd, "-x")
    else
        table.insert(term_cmd, "-e")
    end
    etime = (uv.hrtime() - etime) / 1000000000
    require("r.edit").add_to_debug_info("external term setup", etime, "Time")
end

local M = {}

M.start = function()
    if vim.fn.executable("tmux") == 0 then
        config.external_term = ""
        warn("tmux executable not found")
        return
    end

    if config.config_tmux then
        -- Create a custom tmux.conf
        local cnflines = {
            "set-option -g prefix C-a",
            "unbind-key C-b",
            "bind-key C-a send-prefix",
            "set-window-option -g mode-keys vi",
            "set -g status off",
            'set -g default-terminal "screen-256color"',
            "set -g terminal-overrides 'xterm*:smcup@:rmcup@'",
        }

        if vim.fn.executable("/bin/sh") == 1 then
            table.insert(cnflines, 'set-option -g default-shell "/bin/sh"')
        end

        if term_name == "rxvt" or term_name == "urxvt" then
            table.insert(cnflines, "set terminal-overrides 'rxvt*:smcup@:rmcup@'")
        end

        if term_name == "alacritty" then
            table.insert(cnflines, "set terminal-overrides 'alacritty:smcup@:rmcup@'")
        end

        vim.fn.writefile(cnflines, config.tmpdir .. "/tmux.conf")
        require("r.edit").add_for_deletion(config.tmpdir .. "/tmux.conf")
    end

    if term_name == nil then external_term_config() end

    local open_cmd

    local rargs = require("r.run").get_r_args()
    if rargs ~= "" then rargs = " " .. rargs end
    local rcmd = "RNVIM_TMPDIR="
        .. config.tmpdir:gsub(" ", "\\ ")
        .. " RNVIM_COMPLDIR="
        .. config.compldir:gsub(" ", "\\ ")
        .. " RNVIM_ID="
        .. vim.env.RNVIM_ID
        .. " RNVIM_SECRET="
        .. vim.env.RNVIM_SECRET
        .. " RNVIM_PORT="
        .. vim.env.RNVIM_PORT
        .. " R_DEFAULT_PACKAGES="
        .. vim.env.R_DEFAULT_PACKAGES
        .. " "
        .. config.R_app
        .. rargs

    open_cmd = {}
    for _, v in pairs(term_cmd) do
        table.insert(open_cmd, v)
    end

    if
        vim.tbl_contains(term_cmd, "tmux") and vim.tbl_contains(term_cmd, "split-window")
    then
        is_tmux_split = true
        table.insert(open_cmd, rcmd)
    elseif term_name == "konsole" then
        table.insert(
            open_cmd,
            "tmux -L Rnvim -2 -f "
                .. config.tmpdir
                .. "/tmux.conf new-session -s "
                .. tmuxsname
                .. ' "'
                .. rcmd
                .. '"'
        )
    else
        table.insert(open_cmd, "tmux")
        table.insert(open_cmd, "-L")
        table.insert(open_cmd, "Rnvim")
        table.insert(open_cmd, "-2")
        if config.config_tmux then
            table.insert(open_cmd, "-f")
            table.insert(open_cmd, config.tmpdir .. "/tmux.conf")
        end
        table.insert(open_cmd, "new-session")
        table.insert(open_cmd, "-s")
        table.insert(open_cmd, tmuxsname)
        table.insert(open_cmd, rcmd)
    end

    require("r.term").start(open_cmd, false)
end

--- Send line of command to R Console
---@param command string
---@return boolean
M.send_cmd = function(command)
    local cmd = require("r.term").sanitize(command, true)
    local scmd

    if is_tmux_split then
        scmd = { "tmux", "set-buffer", cmd .. "\n" }
    else
        scmd = { "tmux", "-L", "Rnvim", "set-buffer", cmd .. "\n" }
    end
    local obj = vim.system(scmd):wait()
    if obj.code ~= 0 then
        warn(obj.stderr)
        require("r.run").clear_R_info()
        return false
    end

    if is_tmux_split then
        scmd = { "tmux", "paste-buffer", "-t", r_pane }
    else
        scmd = {
            "tmux",
            "-L",
            "Rnvim",
            "paste-buffer",
            "-t",
            tmuxsname .. "." .. r_pane,
        }
    end

    local res = require("r.term").send(scmd)
    return res
end

--- Return Tmux target name
---@return string
M.get_tmuxsname = function() return tmuxsname and tmuxsname or "" end

--- Set number of Tmux pane where R is running
---@param p string
M.set_r_pane = function(p) r_pane = p end

return M
