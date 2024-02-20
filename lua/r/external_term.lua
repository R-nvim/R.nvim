local config = require("r.config").get_config()
local utils = require("r.utils")
local warn = require("r").warn
local vit = require("r.utils").value_in_table

local term_name = nil
local term_cmd = nil
local tmuxsname = nil
local base_pane_index = nil

-- local global_option_value = TmuxOption("some_option", "global")
-- local window_option_value = TmuxOption("some_option", "")

local external_term_config = function()
    -- The Object Browser can run in a Tmux pane only if Neovim is inside a Tmux session
    config.objbr_place = string.gsub(config.objbr_place, "console", "script")

    tmuxsname = "Rnvim-" .. tostring(vim.fn.localtime()):gsub(".*(...)", "%1")

    if config.is_darwin then return end

    if type(config.external_term) == "string" then
        -- User defined terminal
        term_name = string.gsub(tostring(config.external_term), " .*", "")
        if string.find(tostring(config.external_term), " ") then
            -- Complete command defined by the user
            term_cmd = config.external_term
            return
        end
    end

    local etime = vim.fn.reltime()
    if type(config.external_term) == "boolean" then
        -- Terminal name not defined. Try to find a known one.
        local terminals = {
            "kitty",
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
            "Please, set the value of `external_term` as either the name or the complete command to run your terminal emulator."
        )
    end

    if vit(term_name, { "foot", "gnome-terminal", "xfce4-terminal", "alacritty" }) then
        term_cmd = term_name .. " --title R"
    elseif vit(term_name, { "xterm", "uxterm", "lxterm" }) then
        term_cmd = term_name .. " -title R"
    else
        term_cmd = term_name
    end

    if term_name == "foot" then term_cmd = term_cmd .. " --log-level error" end

    if not config.nvim_wd then
        if
            vit(term_name, { "gnome-terminal", "xfce4-terminal", "lxterminal", "foot" })
        then
            term_cmd = term_cmd
                .. " --working-directory='"
                .. vim.fn.expand("%:p:h")
                .. "'"
        elseif term_name == "konsole" then
            term_cmd = term_cmd
                .. " -p tabtitle=R --workdir '"
                .. vim.fn.expand("%:p:h")
                .. "'"
        elseif term_name == "roxterm" then
            term_cmd = term_cmd .. " --directory='" .. vim.fn.expand("%:p:h") .. "'"
        end
    end

    if term_name == "gnome-terminal" then
        term_cmd = term_cmd .. " --"
    elseif vit(term_name, { "terminator", "xfce4-terminal" }) then
        term_cmd = term_cmd .. " -x"
    else
        term_cmd = term_cmd .. " -e"
    end
    require("r.edit").add_to_debug_info(
        "external term setup",
        vim.fn.reltimefloat(vim.fn.reltime(etime, vim.fn.reltime())),
        "Time"
    )
end

local M = {}

M.start_extern_term = function(Rcmd)
    local tmuxcnf = " "
    if config.config_tmux then
        tmuxcnf = '-f "' .. config.tmpdir .. "/tmux.conf" .. '"'

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

    local cmd = "RNVIM_TMPDIR="
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
        .. Rcmd

    if config.is_darwin then
        open_cmd = string.format(
            "tmux -L Rnvim -2 %s new-session -s %s '%s'",
            tmuxcnf,
            tmuxsname,
            cmd
        )
        local open_file = vim.fn.tempname() .. "/openR"
        vim.fn.writefile({ "#!/bin/sh", open_cmd }, open_file)
        vim.fn.system("chmod +x '" .. open_file .. "'")
        open_cmd = "open '" .. open_file .. "'"
    elseif term_name == "konsole" then
        open_cmd = string.format(
            "%s 'tmux -L Rnvim -2 %s new-session -s %s \"%s\"'",
            term_cmd,
            tmuxcnf,
            tmuxsname,
            cmd
        )
    else
        open_cmd = string.format(
            '%s tmux -L Rnvim -2 %s new-session -s %s "%s"',
            term_cmd,
            tmuxcnf,
            tmuxsname,
            cmd
        )
    end

    vim.g.R_Nvim_status = 6
    if config.silent_term then
        open_cmd = open_cmd .. " &"
        local rlog = vim.fn.system(open_cmd)
        if vim.v.shell_error ~= 0 then
            warn(rlog)
            return
        end
    else
        local initterm = {
            'cd "' .. vim.fn.getcwd() .. '"',
            open_cmd,
        }
        local init_file = config.tmpdir
            .. "/initterm_"
            .. vim.fn.reltimefloat(vim.fn.reltime())
            .. ".sh"
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
M.send_cmd_to_external_term = function(command)
    local cmd = command

    if config.clear_line then
        if config.editing_mode == "emacs" then
            cmd = "\001\011" .. cmd
        else
            cmd = "\0270Da" .. cmd
        end
    end

    -- Send the command to R running in an external terminal emulator
    local str = cmd:gsub("'", "'\\\\''")
    if str:find("^-") then str = " " .. str end

    if not base_pane_index then
        local obj = utils.system(
            { "tmux", "-L", "Rnvim show-options", "-gv", "pane-base-index" },
            { text = true }
        ):wait()
        base_pane_index = obj.stdout:gsub("\n+$", "")
    end
    local scmd
    scmd = string.format(
        "tmux -L Rnvim set-buffer '%s\n' ; tmux -L Rnvim paste-buffer -t %s.%s",
        str,
        tmuxsname,
        base_pane_index
    )

    local rlog = vim.fn.system(scmd)
    if vim.v.shell_error ~= 0 then
        rlog = rlog:gsub("\n", " "):gsub("\r", " ")
        warn(rlog)
        require("r.run").clear_R_info()
        return false
    end
    return true
end

return M
