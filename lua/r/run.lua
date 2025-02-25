local M = {}
local config = require("r.config").get_config()
local job = require("r.job")
local edit = require("r.edit")
local warn = require("r.log").warn
local utils = require("r.utils")
local send = require("r.send")
local cursor = require("r.cursor")
local hooks = require("r.hooks")
local what_R = "R"
local R_pid = 0
local r_args
local nseconds
local uv = vim.uv

local start_R2
start_R2 = function()
    if vim.g.R_Nvim_status == 4 then
        vim.fn.timer_start(30, start_R2)
        return
    end

    r_args = table.concat(config.R_args, " ")
    if what_R:find("custom") then
        vim.ui.input({ prompt = "Enter parameters for R: " }, function(input)
            if input then r_args = input end
        end)
    end

    vim.fn.writefile({}, config.localtmpdir .. "/globenv_" .. vim.env.RNVIM_ID)
    vim.fn.writefile({}, config.localtmpdir .. "/liblist_" .. vim.env.RNVIM_ID)

    edit.add_for_deletion(config.localtmpdir .. "/globenv_" .. vim.env.RNVIM_ID)
    edit.add_for_deletion(config.localtmpdir .. "/liblist_" .. vim.env.RNVIM_ID)

    if vim.o.encoding == "utf-8" then
        edit.add_for_deletion(config.tmpdir .. "/start_options_utf8.R")
    else
        edit.add_for_deletion(config.tmpdir .. "/start_options.R")
    end

    -- Required to make R load nvimcom without the need for the user to include
    -- library(nvimcom) in his or her ~/.Rprofile.
    local rdp
    if vim.env.R_DEFAULT_PACKAGES then
        rdp = vim.env.R_DEFAULT_PACKAGES
        if not rdp:find(",nvimcom") then rdp = rdp .. ",nvimcom" end
    else
        rdp = "datasets,utils,grDevices,graphics,stats,methods,nvimcom"
    end
    vim.env.R_DEFAULT_PACKAGES = rdp

    local start_options = {
        'Sys.setenv(R_DEFAULT_PACKAGES = "' .. rdp:gsub(",nvimcom", "") .. '")',
        'Sys.setenv(RNVIM_RSLV_CB = "' .. vim.env.RNVIM_RSLV_CB .. '")',
        "options(nvimcom.max_depth = " .. tostring(config.compl_data.max_depth) .. ")",
        "options(nvimcom.max_size = " .. tostring(config.compl_data.max_size) .. ")",
        "options(nvimcom.max_time = " .. tostring(config.compl_data.max_time) .. ")",
        'options(nvimcom.set_params = "' .. config.set_params .. '")',
    }
    if config.debug then
        table.insert(start_options, "options(nvimcom.debug_r = TRUE)")
    else
        table.insert(start_options, "options(nvimcom.debug_r = FALSE)")
    end
    if config.objbr_allnames then
        table.insert(start_options, "options(nvimcom.allnames = TRUE)")
    else
        table.insert(start_options, "options(nvimcom.allnames = FALSE)")
    end
    if config.texerr then
        table.insert(start_options, "options(nvimcom.texerrs = TRUE)")
    else
        table.insert(start_options, "options(nvimcom.texerrs = FALSE)")
    end

    local has_cmp_r, _ = pcall(require, "cmp_r")
    if has_cmp_r then
        table.insert(start_options, "options(nvimcom.autoglbenv = 2)")
    else
        table.insert(start_options, "options(nvimcom.autoglbenv = 0)")
    end
    if config.setwidth == 2 then
        table.insert(start_options, "options(nvimcom.setwidth = TRUE)")
    else
        table.insert(start_options, "options(nvimcom.setwidth = FALSE)")
    end
    if config.nvimpager == "no" then
        table.insert(start_options, "options(nvimcom.nvimpager = FALSE)")
    else
        table.insert(start_options, "options(nvimcom.nvimpager = TRUE)")
    end
    if config.external_term == "" and config.esc_term then
        table.insert(start_options, "options(editor = nvimcom:::nvim.edit)")
    end
    if config.external_term ~= "" then
        table.insert(
            start_options,
            "reg.finalizer(.GlobalEnv, nvimcom:::final_msg, onexit = TRUE)"
        )
    end
    local sep = config.view_df.csv_sep or "\t"
    table.insert(start_options, 'options(nvimcom.delim = "' .. sep .. '")')
    table.insert(
        start_options,
        'options(nvimcom.source.path = "' .. config.source_read .. '")'
    )
    if
        config.set_params ~= "no"
        and (vim.o.filetype == "quarto" or vim.o.filetype == "rmd")
        and require("r.rmd").params_status() == "new"
    then
        local bn = vim.api.nvim_buf_get_name(0)
        if config.is_windows then bn = bn:gsub("\\", "\\\\") end
        table.insert(start_options, 'nvimcom:::update_params("' .. bn .. '")')
    end

    local rsd = M.get_R_start_dir()
    if rsd then
        -- `rwd` will not be a real directory if editing a file on the internet
        -- with netrw plugin
        if vim.fn.isdirectory(rsd) == 1 then
            table.insert(start_options, 'setwd("' .. rsd .. '")')
        end
    end

    if vim.o.encoding == "utf-8" then
        vim.fn.writefile(start_options, config.tmpdir .. "/start_options_utf8.R")
    else
        vim.fn.writefile(start_options, config.tmpdir .. "/start_options.R")
    end

    if config.RStudio_cmd ~= "" then
        vim.env.R_DEFAULT_PACKAGES = rdp .. ",rstudioapi"
        require("r.rstudio").start()
        return
    end

    if config.external_term == "" then
        require("r.term").start()
        return
    end

    if config.is_windows then
        warn(
            "Support for running Rgui.exe may be removed. Please, see https://github.com/R-nvim/R.nvim/issues/308"
        )
        require("r.rgui").start()
        return
    end

    require("r.external_term").start()
end

--- Return arguments to start R defined as config.R_args or during custom R
--- start.
---@return string
M.get_r_args = function() return r_args end

--- Register rnvimserver port in a environment variable
---@param p string
M.set_rns_port = function(p)
    vim.g.R_Nvim_status = 5
    vim.env.RNVIM_PORT = p
end

M.start_R = function(whatr)
    -- R started and nvimcom loaded
    if vim.g.R_Nvim_status == 7 then
        if config.external_term == "" then require("r.term").reopen_win() end
        return
    end

    if config.external_term:find("tmux split%-window") and not vim.env.TMUX_PANE then
        warn("Neovim must be running within Tmux to run `tmux split-window`.")
        return
    end

    -- R already started
    if vim.g.R_Nvim_status == 6 then return end

    if vim.g.R_Nvim_status == 4 then
        warn("Cannot start R: TCP server not ready yet.")
        return
    end
    if vim.g.R_Nvim_status == 5 then
        warn("R is already starting...")
        return
    end
    if vim.g.R_Nvim_status == 2 then
        warn("Cannot start R: rnvimserver not ready yet.")
        return
    end

    if vim.g.R_Nvim_status == 1 then
        warn("Cannot start R: rnvimserver not started yet.")
        return
    end

    if vim.g.R_Nvim_status == 3 then
        vim.g.R_Nvim_status = 4
        require("r.send").set_send_cmd_fun()
        job.stdin("Server", "1\n") -- Start the TCP server
        what_R = whatr
        vim.fn.timer_start(30, start_R2)
        return
    end
end

---Send signal to R
---@param signal string | number
M.signal_to_R = function(signal)
    if R_pid ~= 0 then vim.system({ "kill", "-s", tostring(signal), tostring(R_pid) }) end
end

M.check_nvimcom_running = function()
    nseconds = nseconds - 1
    if R_pid == 0 then
        if nseconds > 0 then
            vim.fn.timer_start(1000, M.check_nvimcom_running)
        else
            local msg =
                "The package nvimcom wasn't loaded yet. Please, quit R and try again."
            warn(msg)
        end
    end
end

M.wait_nvimcom_start = function()
    if string.find(r_args, "vanilla") then return 0 end

    if config.wait < 2 then config.wait = 2 end

    nseconds = config.wait
    vim.fn.timer_start(1000, M.check_nvimcom_running)
end

M.set_nvimcom_info = function(nvimcomversion, rpid, wid, r_info)
    local r_home_description =
        vim.fn.readfile(config.rnvim_home .. "/nvimcom/DESCRIPTION")
    local current
    for _, v in pairs(r_home_description) do
        if v:find("Version: ") then current = v:sub(10) end
    end
    if nvimcomversion ~= current then
        warn(
            "Mismatch in nvimcom versions: R ("
                .. nvimcomversion
                .. ") and Vim ("
                .. current
                .. ")"
        )
        vim.wait(1000)
    end

    R_pid = rpid
    vim.env.RCONSOLE = wid

    -- R_version = r_info[1]
    config.OutDec = r_info.OutDec
    config.R_prompt_str = r_info.prompt:gsub(" $", "")
    config.R_continue_str = r_info.continue:gsub(" $", "")

    if not r_info.has_color and config.hl_term then require("r.term").highlight_term() end

    config.R_Tmux_pane = r_info.tmux_pane

    if job.is_running("Server") then
        if config.is_windows then
            if vim.env.RCONSOLE == "0" then warn("nvimcom did not save R window ID") end
        end
    else
        warn("nvimcom is not running")
    end

    if config.RStudio_cmd ~= "" then
        if
            config.is_windows
            and config.arrange_windows
            and vim.fn.filereadable(config.compldir .. "/win_pos") == 1
        then
            job.stdin("Server", "85" .. config.compldir .. "\n")
        end
    elseif config.is_windows then
        if
            config.arrange_windows
            and vim.fn.filereadable(config.compldir .. "/win_pos") == 1
        then
            job.stdin("Server", "85" .. config.compldir .. "\n")
        end
    end

    if config.objbr_auto_start then
        if config.is_windows then
            -- Give R some time to be ready
            vim.fn.timer_start(1010, require("r.browser").start)
        else
            vim.schedule(require("r.browser").start)
        end
    end

    vim.g.R_Nvim_status = 7
    hooks.run(config, "after_R_start", true)
    send.set_send_cmd_fun()
end

M.clear_R_info = function()
    vim.fn.delete(config.tmpdir .. "/globenv_" .. vim.fn.string(vim.env.RNVIM_ID))
    vim.fn.delete(config.localtmpdir .. "/liblist_" .. vim.fn.string(vim.env.RNVIM_ID))
    R_pid = 0
    if config.external_term == "" then require("r.term").close_term() end
    if job.is_running("Server") then
        vim.g.R_Nvim_status = 3
        job.stdin("Server", "43\n")
    else
        vim.g.R_Nvim_status = 1
    end
    send.set_send_cmd_fun()
    require("r.rmd").clean_params()
end

-- Background communication with R

---Send a message to rnvimserver job which will send the message to nvimcom
---through a TCP connection.
---@param code string Single letter to be interpreted by nvimcom
---@param attch string Additional command to be evaluated by nvimcom
M.send_to_nvimcom = function(code, attch)
    if vim.g.R_Nvim_status < 6 then
        warn("R is not running")
        return
    end

    if vim.g.R_Nvim_status < 7 then
        warn("R is not ready yet")
        return
    end

    if not job.is_running("Server") then
        warn("Server not running.")
        return
    end
    job.stdin("Server", "2" .. code .. vim.env.RNVIM_ID .. attch .. "\n")
end

M.quit_R = function(how)
    local qcmd
    if how == "save" then
        qcmd = 'quit(save = "yes")'
    else
        qcmd = 'quit(save = "no")'
    end

    if config.is_windows then
        if config.external_term ~= "" then
            -- SaveWinPos
            job.stdin(
                "Server",
                "84" .. vim.fn.escape(vim.env.RNVIM_COMPLDIR, "\\") .. "\n"
            )
        end
        job.stdin("Server", "2QuitNow\n")
    end

    local bb = require("r.browser").get_buf_nr()
    if bb then
        vim.cmd("bunload! " .. tostring(bb))
        vim.wait(30)
    end

    require("r.send").cmd(qcmd)
end

---Request R to format code
---@param tbl table Table sent by Neovim's mapping function
M.format_code = function(tbl)
    if vim.g.R_Nvim_status < 7 then return end

    local wco = vim.o.textwidth
    if wco == 0 then
        wco = 78
    elseif wco < 20 then
        wco = 20
    elseif wco > 180 then
        wco = 180
    end

    if tbl.range == 0 then
        vim.cmd("update")
        M.send_to_nvimcom(
            "E",
            "nvimcom:::nvim_format_file('"
                .. vim.api.nvim_buf_get_name(0)
                .. "', "
                .. wco
                .. ", "
                .. vim.o.shiftwidth
                .. ")"
        )
    else
        local lns = vim.api.nvim_buf_get_lines(0, tbl.line1 - 1, tbl.line2, true)
        local txt = table.concat(lns, "\020")
        txt = txt:gsub("\\", "\\\\"):gsub("'", "\019")
        M.send_to_nvimcom(
            "E",
            "nvimcom:::nvim_format_txt("
                .. tbl.line1
                .. ", "
                .. tbl.line2
                .. ", "
                .. wco
                .. ", "
                .. vim.o.shiftwidth
                .. ", '"
                .. txt
                .. "')"
        )
    end
end

--- Request R to evaluate a command and send its output back
---@param cmd string
---@param type string
M.insert = function(cmd, type)
    if vim.g.R_Nvim_status < 7 then return end
    M.send_to_nvimcom("E", "nvimcom:::nvim_insert(" .. cmd .. ', "' .. type .. '")')
end

M.insert_commented = function()
    local lin = vim.api.nvim_get_current_line()
    local cleanl = lin:gsub('".-"', "")
    if cleanl:find(";") then
        warn("`print(line)` works only if `line` is a single command")
    end
    cleanl = string.gsub(lin, "%s*#.*", "")
    M.insert("print(" .. cleanl .. ")", "comment")
end

---Get the word either under or after the cursor.
---Works for word(| where | is the cursor position.
---@return string
M.get_keyword = function()
    local line = vim.api.nvim_get_current_line()
    local llen = #line
    if llen == 0 then return "" end

    local i = vim.api.nvim_win_get_cursor(0)[2] + 1

    -- Skip opening braces
    local char
    while i > 1 do
        char = line:sub(i, i)
        if char == "[" or char == "(" or char == "{" then
            i = i - 1
        else
            break
        end
    end

    -- Go to the beginning of the word
    while
        i > 1
        and (
            line:sub(i - 1, i - 1):match("[%w@:$:_%.]")
            or (line:byte(i - 1) > 0x80 and line:byte(i - 1) < 0xf5)
        )
    do
        i = i - 1
    end
    -- Go to the end of the word
    local j = i
    local b
    while j <= llen do
        b = line:byte(j + 1)
        if
            b and ((b > 0x80 and b < 0xf5) or line:sub(j + 1, j + 1):match("[%w@$:_%.]"))
        then
            j = j + 1
        else
            break
        end
    end
    return line:sub(i, j)
end

---Call R functions for the word under cursor
---@param rcmd string Function to call or action to execute
---@param mode string Vim's mode ("n" or "v")
---@param args string Additional argument on how to call the function
M.action = function(rcmd, mode, args)
    local rkeyword

    if vim.o.syntax == "rbrowser" then
        local lnum = vim.api.nvim_win_get_cursor(0)[1]
        local line = vim.fn.getline(lnum)
        rkeyword = require("r.browser").get_name(lnum, line)
    elseif
        mode
        and mode == "v"
        and vim.api.nvim_buf_get_mark(0, "<")[1]
            == vim.api.nvim_buf_get_mark(0, ">")[1]
    then
        local lnum = vim.api.nvim_buf_get_mark(0, ">")[1]
        if lnum then
            rkeyword = vim.fn.strpart(
                vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1],
                vim.fn.col("'<") - 1,
                vim.fn.col("'>") - vim.fn.col("'<") + 1
            )
        end
    else
        rkeyword = M.get_keyword()
    end

    if not rkeyword or #rkeyword == 0 then return end

    if rcmd == "help" then
        local rhelppkg, rhelptopic
        if rkeyword:find("::") then
            local rhelplist = vim.fn.split(rkeyword, "::")
            rhelppkg = rhelplist[1]
            rhelptopic = rhelplist[2]
        else
            rhelppkg = ""
            rhelptopic = rkeyword
        end
        if config.nvimpager == "no" then
            send.cmd("help(" .. rkeyword .. ")")
        else
            if vim.api.nvim_get_current_buf() == require("r.browser").get_buf_nr() then
                if require("r.browser").get_curview() == "libraries" then
                    rhelppkg = require("r.browser").get_pkg_name()
                end
            end
            require("r.doc").ask_R_doc(rhelptopic, rhelppkg, true)
        end
        return
    end

    if rcmd == "print" then
        M.print_object(rkeyword)
        return
    end

    local rfun = rcmd

    if rcmd == "args" then
        if config.listmethods and not rkeyword:find("::") then
            send.cmd('nvim.list.args("' .. rkeyword .. '")')
        else
            send.cmd("args(" .. rkeyword .. ")")
        end

        return
    end

    if rcmd == "plot" and config.specialplot then rfun = "nvim.plot" end

    if rcmd == "plotsumm" then
        local raction

        if config.specialplot then
            raction = "nvim.plot(" .. rkeyword .. "); summary(" .. rkeyword .. ")"
        else
            raction = "plot(" .. rkeyword .. "); summary(" .. rkeyword .. ")"
        end

        send.cmd(raction)
        return
    end

    if config.open_example and rcmd == "example" then
        M.send_to_nvimcom("E", 'nvimcom:::nvim.example("' .. rkeyword .. '")')
        return
    end

    if rcmd == "viewobj" then
        local n_lines = config.view_df.n_lines or -1
        local argmnts = ", nrows = " .. tostring(n_lines)
        if config.view_df.open_fun and config.view_df.open_fun ~= "" then
            local cmd = config.view_df.open_fun
            if cmd:find("%(%)") then
                cmd = cmd:gsub("()", "(" .. rkeyword .. ")")
            elseif cmd:find("%%s") then
                cmd = cmd:gsub("%%s", rkeyword)
            else
                cmd = cmd .. "(" .. rkeyword .. ")"
            end
            cmd = cmd:gsub("'", '"')
            cmd = cmd:gsub('"', '\\"')
            argmnts = argmnts .. ', R_df_viewer = "' .. cmd .. '"'
        end
        if config.view_df.save_fun and config.view_df.save_fun ~= "" then
            argmnts = argmnts .. ", save_fun = " .. config.view_df.save_fun
        end
        if rkeyword:find("::") then
            M.send_to_nvimcom(
                "E",
                "nvimcom:::nvim_viewobj(" .. rkeyword .. argmnts .. ")"
            )
        else
            local fenc = config.is_windows
                    and vim.o.encoding == "utf-8"
                    and ', fenc="UTF-8"'
                or ""
            M.send_to_nvimcom(
                "E",
                'nvimcom:::nvim_viewobj("' .. rkeyword .. '"' .. argmnts .. fenc .. ")"
            )
        end
        return
    end

    local argmnts = args or ""
    if rcmd == "dputtab" then
        M.send_to_nvimcom(
            "E",
            'nvimcom:::nvim_dput("' .. rkeyword .. '"' .. argmnts .. ")"
        )
        return
    end
    local raction = rfun .. "(" .. rkeyword .. argmnts .. ")"
    send.cmd(raction)
end

---Send the print() command to R with rkeyword as parameter
---@param rkeyword string
M.print_object = function(rkeyword)
    local firstobj

    if vim.api.nvim_get_current_buf() == require("r.browser").get_buf_nr() then
        firstobj = ""
    else
        firstobj = cursor.get_first_obj()
    end

    if firstobj == "" then
        send.cmd("print(" .. rkeyword .. ")")
    else
        send.cmd('nvim.print("' .. rkeyword .. '", "' .. firstobj .. '")')
    end
end

-- knit the current buffer content
M.knit = function()
    vim.cmd("update")
    send.cmd(
        "require(knitr); .nvim_oldwd <- getwd(); setwd('"
            .. M.get_buf_dir()
            .. "'); knit('"
            .. vim.fn.expand("%:t")
            .. "'); setwd(.nvim_oldwd); rm(.nvim_oldwd)"
    )
end

-- Set working directory to the path of current buffer
M.setwd = function() send.cmd('setwd("' .. M.get_buf_dir() .. '")') end

M.show_obj = function(howto, bname, ftype, txt)
    local bfnm = bname:gsub("[^%w]", "_")
    edit.add_for_deletion(config.tmpdir .. "/" .. bfnm)
    vim.cmd({ cmd = howto, args = { config.tmpdir .. "/" .. bfnm } })
    vim.o.filetype = ftype
    local lines = vim.split(txt:gsub("\019", "'"), "\020")
    vim.api.nvim_buf_set_lines(0, 0, 0, true, lines)
    vim.api.nvim_buf_set_var(0, "modified", false)
end

-- Clear the console screen
M.clear_console = function()
    if config.clear_console == false then return end

    if config.is_windows and config.external_term ~= "" then
        job.stdin("Server", "86\n")
        vim.wait(50)
        job.stdin("Server", "87\n")
    else
        send.cmd("\012")
    end
end

M.clear_all = function()
    if config.rmhidden then
        M.send.cmd("rm(list=ls(all.names = TRUE))")
    else
        send.cmd("rm(list = ls())")
    end
    vim.wait(30)
    M.clear_console()
end

M.get_buf_dir = function()
    local rwd = vim.api.nvim_buf_get_name(0)
    if config.is_windows then rwd = utils.normalize_windows_path(rwd) end
    rwd = rwd:gsub("(.*)/.*", "%1")
    return rwd
end

---Get the directory where R should start
---@return string | nil
M.get_R_start_dir = function()
    if not config.remote_compldir == "" then return nil end
    local rsd
    if config.setwd == "file" then
        rsd = M.get_buf_dir()
    elseif config.setwd == "nvim" then
        rsd = uv.cwd()
        if rsd and config.is_windows then rsd = rsd:gsub("\\", "/") end
    end
    return rsd
end

---Send to R the command to source all files in a directory
---@param dir string
M.source_dir = function(dir)
    if config.is_windows then dir = utils.normalize_windows_path(dir) end
    if dir == "" then
        send.cmd("nvim.srcdir()")
    else
        send.cmd("nvim.srcdir('" .. dir .. "')")
    end
end

return M
