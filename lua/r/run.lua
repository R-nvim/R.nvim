local M = {}
local Rsource_read
local config = require("r.config").get_config()
local job = require("r.job")
local edit = require("r.edit")
local warn = require("r").warn
local utils = require("r.utils")
local autosttobjbr
local my_port = 0
local R_pid = 0
local r_args
local wait_nvimcom = 0
local waiting_to_start_r = ''
local nseconds

local get_buf_dir = function()
    local rwd = vim.api.nvim_buf_get_name(0)
    if config.is_windows then
        rwd = vim.fn.substitute(rwd, '\\', '/', 'g')
        rwd = utils.nomralize_windows_path(rwd)
    end
    rwd = vim.fn.substitute(rwd, '\\(.*\\)/.*', '\\1', '')
    return rwd
end

local set_send_cmd_fun = function ()
    require("r.send").set_send_cmd_fun()
    vim.g.R_Nvim_status = 5
    wait_nvimcom = 0
end

M.set_my_port = function (p)
    my_port = p
    vim.env.NVIMR_PORT = p
    if waiting_to_start_r ~= '' then
        M.start_R(waiting_to_start_r)
        waiting_to_start_r = ''
    end
end

M.auto_start_R = function ()
    if vim.g.R_Nvim_status > 3 then
        return
    end
    if vim.v.vim_did_enter == 0 or vim.g.R_Nvim_status < 3 then
        vim.fn.timer_start(100, M.auto_start_R)
        return
    end
    M.start_R("R")
end

M.start_R = function (whatr)
    vim.g.R_Nvim_status = 3
    wait_nvimcom = 1
    require("r.send").cmd = require("r.send").not_ready

    if my_port == 0 then
        local running = require("r.job").is_running("Server")
        if not running then
            warn("Cannot start R: nvimrserver not running")
            return
        end
        if vim.g.R_Nvim_status < 3 then
            warn("nvimrserver not ready yet")
            return
        end
        waiting_to_start_r = whatr
        job.stdin("Server", "1\n") -- Start the TCP server
        return
    end

    if (type(config.external_term) == "boolean" and config.external_term) or type(config.external_term) == "string" then
        config.objbr_place = vim.fn.substitute(config.objbr_place, 'console', 'script', '')
    end

    if whatr:find("custom") then
        r_args = vim.fn.split(vim.fn.input('Enter parameters for R: '))
    else
        r_args = config.R_args
    end

    vim.fn.writefile({}, config.localtmpdir .. "/globenv_" .. vim.env.NVIMR_ID)
    vim.fn.writefile({}, config.localtmpdir .. "/liblist_" .. vim.env.NVIMR_ID)

    edit.add_for_deletion(config.localtmpdir .. "/globenv_" .. vim.env.NVIMR_ID)
    edit.add_for_deletion(config.localtmpdir .. "/liblist_" .. vim.env.NVIMR_ID)

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
        if not rdp:find(",nvimcom") then
            rdp = rdp .. ",nvimcom"
        end
    else
        rdp = "datasets,utils,grDevices,graphics,stats,methods,nvimcom"
    end
    vim.env.R_DEFAULT_PACKAGES = rdp
    local start_options = {
        'Sys.setenv("R_DEFAULT_PACKAGES" = "' .. rdp .. '")',
    }

    if config.objbr_allnames then
        table.insert(start_options, 'options(nvimcom.allnames = TRUE)')
    else
        table.insert(start_options, 'options(nvimcom.allnames = FALSE)')
    end
    if config.texerr then
        table.insert(start_options, 'options(nvimcom.texerrs = TRUE)')
    else
        table.insert(start_options, 'options(nvimcom.texerrs = FALSE)')
    end
    if config.update_glbenv then
        table.insert(start_options, 'options(nvimcom.autoglbenv = TRUE)')
    else
        table.insert(start_options, 'options(nvimcom.autoglbenv = FALSE)')
    end
    if config.setwidth and config.setwidth == 2 then
        table.insert(start_options, 'options(nvimcom.setwidth = TRUE)')
    else
        table.insert(start_options, 'options(nvimcom.setwidth = FALSE)')
    end
    if config.nvimpager == "no" then
        table.insert(start_options, 'options(nvimcom.nvimpager = FALSE)')
    else
        table.insert(start_options, 'options(nvimcom.nvimpager = TRUE)')
    end
    if type(config.external_term) == "boolean" and not config.external_term and config.esc_term then
        table.insert(start_options, 'options(editor = nvimcom:::nvim.edit)')
    end
    if config.csv_delim and (config.csv_delim == "," or config.csv_delim == ";") then
        table.insert(start_options, 'options(nvimcom.delim = "' .. config.csv_delim .. '")')
    else
        table.insert(start_options, 'options(nvimcom.delim = "\t")')
    end

    if config.remote_compldir then
        Rsource_read = config.remote_compldir .. "/tmp/Rsource-" .. vim.fn.getpid()
    else
        Rsource_read = config.tmpdir .. "/Rsource-" .. vim.fn.getpid()
    end
    table.insert(start_options, 'options(nvimcom.source.path = "' .. Rsource_read .. '")')

    local rwd = ""
    if config.nvim_wd == 0 then
        rwd = get_buf_dir()
    elseif config.nvim_wd == 1 then
        rwd = vim.fn.getcwd()
    end
    if rwd ~= "" and not config.remote_compldir then
        if config.is_windows then
            rwd = vim.fn.substitute(rwd, '\\', '/', 'g')
        end

        -- `rwd` will not be a real directory if editing a file on the internet
        -- with netrw plugin
        if vim.fn.isdirectory(rwd) == 1 then
            table.insert(start_options, 'setwd("' .. rwd .. '")')
        end
    end

    if vim.o.encoding == "utf-8" then
        vim.fn.writefile(start_options, config.tmpdir .. "/start_options_utf8.R")
    else
        vim.fn.writefile(start_options, config.tmpdir .. "/start_options.R")
    end

    if vim.fn.exists("g:RStudio_cmd") == 1 then
        vim.env.R_DEFAULT_PACKAGES = rdp .. ",rstudioapi"
        require("r.rstudio").start_RStudio()
        return
    end

    if type(config.external_term) == "boolean" and config.external_term == false then
        require("r.term").start_term()
        return
    end

    if config.applescript then
        require("r.osx").start_Rapp()
        return
    end

    if config.is_windows then
        require("r.windows").start_Rgui()
        return
    end

    local args_str = table.concat(r_args, " ")
    local rcmd = config.R_app .. " " .. args_str

    require("r.external_term").start_extern_term(rcmd)
end

-- Send SIGINT to R
M.signal_to_R = function(signal)
    if R_pid ~= 0 then
        vim.system({'kill', '-s', tostring(signal), tostring(R_pid)})
    end
end

M.check_nvimcom_running = function ()
    nseconds = nseconds - 1
    if R_pid == 0 then
        if nseconds > 0 then
            vim.fn.timer_start(1000, M.check_nvimcom_running)
        else
            local msg = "The package nvimcom wasn't loaded yet. Please, quit R and try again."
            warn(msg)
            vim.wait(500)
        end
    end
end

M.wait_nvimcom_start = function()
    local args_str = table.concat(r_args, ' ')
    if string.find(args_str, "vanilla") then
        return 0
    end

    if config.wait < 2 then
        config.wait = 2
    end

    nseconds = config.wait
    vim.fn.timer_start(1000, M.check_nvimcom_running)
end

M.set_nvimcom_info = function (nvimcomversion, rpid, wid, r_info)
    local r_home_description = vim.fn.readfile(config.rnvim_home .. '/R/nvimcom/DESCRIPTION')
    local current
    for _, v in pairs(r_home_description) do
        if v:find("Version: ") then
            current = v:sub(10)
        end
    end
    if nvimcomversion ~= current then
        warn('Mismatch in nvimcom versions: R (' .. nvimcomversion .. ') and Vim (' .. current .. ')')
        vim.wait(1000)
    end

    R_pid = rpid
    vim.env.RCONSOLE = wid

    local Rinfo = vim.fn.split(r_info, "\x12")
    -- R_version = Rinfo[1]
    config.OutDec = Rinfo[2]
    config.R_prompt_str = vim.fn.substitute(Rinfo[3], ' $', '', '')
    config.R_continue_str = vim.fn.substitute(Rinfo[4], ' $', '', '')

    if Rinfo[5] == '0' and (config.hl_term == nil or config.hl_term) then
        require("r.term").highlight_term()
    end

    if job.is_running("Server") then
        if config.is_windows then
            if vim.env.RCONSOLE == "0" then
                warn("nvimcom did not save R window ID")
            end
        end
    else
        warn("nvimcom is not running")
    end

    if vim.fn.exists("g:RStudio_cmd") == 1 then
        if config.is_windows and config.arrange_windows and
            vim.fn.filereadable(config.compldir .. "/win_pos") == 1 then
            job.stdin("Server", "85" .. config.compldir .. "\n")
        end
    elseif config.is_windows then
        if config.arrange_windows and vim.fn.filereadable(config.compldir .. "/win_pos") == 1 then
            job.stdin("Server", "85" .. config.compldir .. "\n")
        end
    elseif config.applescript then
        vim.fn.foreground()
        vim.wait(200)
    else
        vim.fn.delete(config.tmpdir .. "/initterm_" .. vim.fn.string(vim.env.NVIMR_ID) .. ".sh")
        vim.fn.delete(config.tmpdir .. "/openR")
    end

    if config.objbr_auto_start then
        autosttobjbr = 1
        vim.notify("Not implemented yet autosttobjbr=" .. tostring(autosttobjbr))
        vim.fn.timer_start(1010, "RObjBrowser")
    end

    if config.hook.after_R_start then
        config.hook.after_R_start()
    end
    vim.fn.timer_start(100, set_send_cmd_fun)
end

M.clear_R_info = function()
    vim.fn.delete(config.tmpdir .. "/globenv_" .. vim.fn.string(vim.env.NVIMR_ID))
    vim.fn.delete(config.localtmpdir .. "/liblist_" .. vim.fn.string(vim.env.NVIMR_ID))
    R_pid = 0
    vim.g.R_Nvim_status = 3
    if type(config.external_term) == 'boolean' and config.external_term == false then
        require("r.term").close_term()
    end
    job.stdin("Server", "43\n")
    vim.g.R_Nvim_status = 1
end


-- Background communication with R

-- Send a message to nvimrserver job which will send the message to nvimcom
-- through a TCP connection.
M.send_to_nvimcom = function (code, attch)
    if wait_nvimcom and R_pid == 0 then
        warn("R is not ready yet")
        return
    end
    if R_pid == 0 then
        warn("R is not running")
        return
    end

    if not job.is_running("Server") then
        warn("Server not running.")
        return
    end
    job.stdin("Server", "2" .. code .. vim.env.NVIMR_ID .. attch .. "\n")
end

M.quit_R = function (how)
    local qcmd
    if how == "save" then
        qcmd = 'quit(save = "yes")'
    else
        qcmd = 'quit(save = "no")'
    end

    if config.is_windows then
        if type(config.external_term) == "boolean" and config.external_term then
            -- SaveWinPos
            job.stdin("Server", "84" .. vim.fn.escape(vim.env.NVIMR_COMPLDIR, '\\') .. "\n")
        end
        job.stdin("Server", "2QuitNow\n")
    end

    if vim.fn.bufloaded('Object_Browser') == 1 then
        vim.cmd('bunload! Object_Browser')
        vim.wait(30)
    end

    require("r.send").cmd(qcmd)

    if how == 'save' then
        vim.wait(200)
    end

    vim.wait(50)
    M.clear_R_info()
end

M.formart_code = function (tbl)
    if vim.g.R_Nvim_status < 5 then
        return
    end

    local wco = vim.o.textwidth
    if wco == 0 then
        wco = 78
    elseif wco < 20 then
        wco = 20
    elseif wco > 180 then
        wco = 180
    end

    local lns = vim.api.nvim_buf_get_lines(0, tbl.line1 - 1, tbl.line2, true)
    vim.fn.getline(tbl.line1, tbl.line2)
    local txt = string.gsub(string.gsub(table.concat(lns, "\x14"), '\\', '\\\\'), "'", "\x13")
    M.send_to_nvimcom("E", "nvimcom:::nvim_format(" .. tbl.line1 .. ", " .. tbl.line2 .. ", " .. wco .. ", " .. vim.o.shiftwidth .. ", '" .. txt .. "')")
end

M.insert = function (cmd, type)
    if vim.g.R_Nvim_status < 5 then
        return
    end
    M.send_to_nvimcom("E", 'nvimcom:::nvim_insert(' .. cmd .. ', "' .. type .. '")')
end

M.insert_commented = function()
    local lin = vim.fn.getline(vim.fn.line("."))
    local cleanl = vim.fn.substitute(lin, '".\\{-}"', '', 'g')
    if cleanl:find(";") then
        warn('`print(line)` works only if `line` is a single command')
    end
    cleanl = string.gsub(lin, "%s*#.*", "")
    M.insert("print(" .. cleanl .. ")", "comment")
end

return M
