local edit = require("r.edit")
local utils = require("r.utils")
local job = require("r.job")
local config = require("r.config").get_config()
local warn = require("r").warn
local uv = vim.loop
local b_warn = {}
local b_err = {}
local b_out = {}
local b_time
local libd = nil
local pkgbuild_attempt = false
local rhelp_list = {}

local M = {}

---Callback function to process the stdout of before_nrs.R
local init_stdout = function(_, data, _)
    if not data then return end
    local rcmd = string.gsub(table.concat(data, ""), "\r", "")
    local out_line = ""
    if out_line ~= "" then
        rcmd = out_line .. rcmd
        if rcmd:find("\020") == nil then
            out_line = rcmd
            return
        end
    end
    if
        rcmd:find("^ECHO: ")
        or rcmd:find("^INFO: ")
        or rcmd:find("^WARN: ")
        or rcmd:find("^LIBD: ")
    then
        if rcmd:find("\020") == nil then
            out_line = rcmd
            return
        end
        out_line = ""

        -- In spite of flush(stdout()), rcmd might be concatenating two commands
        local rcmdl = vim.fn.split(rcmd, "\020", 0)
        for _, c in ipairs(rcmdl) do
            if c:find("^WARN: ") then
                table.insert(b_warn, c:sub(7))
            elseif c:find("^LIBD: ") then
                libd = c:sub(7)
            elseif c:find("^ECHO: ") then
                local msg = c:sub(7)
                vim.schedule(function() vim.api.nvim_echo({ { msg } }, false, {}) end)
            elseif c:find("^INFO: ") then
                local info = vim.fn.split(c:sub(7), "=")
                edit.add_to_debug_info(info[1], info[2])
            end
        end
    else
        table.insert(b_out, rcmd)
    end
end

local init_stderr = function(_, data, _)
    if data then
        local s = table.concat(data, "")
        s = string.gsub(s, "\r", "")
        table.insert(b_err, s)
    end
end

local mk_R_dir = function()
    local resp
    vim.schedule(function()
        vim.ui.input(
            { prompt = '"' .. libd .. '" is not writable. Create it now? [y/n] ' },
            function(input) resp = input end
        )
    end)
    if resp and resp:find("y") then
        local dw = vim.fn.mkdir(libd, "p")
        if dw == 1 then
            -- Try again
            M.check_nvimcom_version()
        else
            warn('Failed creating "' .. libd .. '"')
        end
    else
        vim.schedule(function() vim.api.nvim_out_write("\n") end)
    end
    libd = nil
end

---Find the path to the rnvimserver executable in the specified library directory.
---@param libdir string
---@return string
local find_rns_path = function(libdir)
    local nrs
    if config.is_windows then
        nrs = "rnvimserver.exe"
    else
        nrs = "rnvimserver"
    end
    local paths = {
        libdir .. "/bin/" .. nrs,
        libdir .. "/bin/x64/" .. nrs,
        libdir .. "/bin/i386/" .. nrs,
    }
    for _, path in ipairs(paths) do
        if vim.fn.filereadable(path) == 1 then return path end
    end
    warn('Application "' .. nrs .. '" not found at "' .. libdir .. '"')
    return ""
end

-- Check and set some variables and, finally, start the rnvimserver
local start_rnvimserver = function()
    if job.is_running("Server") then return end

    local nrs_path

    if config.local_R_library_dir ~= "" then
        nrs_path = find_rns_path(config.local_R_library_dir .. "/nvimcom")
    else
        local info_path = config.compldir .. "/nvimcom_info"
        if vim.fn.filereadable(info_path) == 1 then
            local info = vim.fn.readfile(info_path)
            if #info == 3 then
                -- Update nvimcom information
                edit.add_to_debug_info(
                    "nvimcom info",
                    { version = info[1], home = info[2], Rversion = info[3] }
                )
                nrs_path = find_rns_path(info[2])
            else
                vim.fn.delete(info_path)
                warn("ERROR in nvimcom_info! Please, do :RDebugInfo for details.")
                return
            end
        else
            warn("ERROR: nvimcom_info not found. Please, run :RDebugInfo for details.")
            return
        end
    end

    local nrs_dir = nrs_path:gsub("/rnvimserver.*", "")

    local nrs_env = {}

    -- Some pdf viewers run rnvimserver to send SyncTeX messages back to Neovim
    if config.is_windows then
        nrs_env["PATH"] = nrs_dir .. ";" .. vim.env.PATH
    else
        nrs_env["PATH"] = nrs_dir .. ":" .. vim.env.PATH
    end

    -- Options in the rnvimserver application are set through environment variables
    if config.objbr_opendf then nrs_env["RNVIM_OPENDF"] = "TRUE" end
    if config.objbr_openlist then nrs_env["RNVIM_OPENLS"] = "TRUE" end
    if config.objbr_allnames then nrs_env["RNVIM_OBJBR_ALLNAMES"] = "TRUE" end
    nrs_env["RNVIM_RPATH"] = config.R_cmd
    nrs_env["RNVIM_LOCAL_TMPDIR"] = config.localtmpdir

    -- We have to set R's home directory on Windows because rnvimserver will
    -- run R to build the list for omni completion.
    if config.is_windows then require("r.windows").set_R_home() end

    local nrs_opts = {
        on_stdout = require("r.job").on_stdout,
        on_stderr = require("r.job").on_stderr,
        on_exit = require("r.job").on_exit,
        env = nrs_env,
    }
    -- require("r.job").start("Server", { "valgrind", "--log-file=/tmp/rnvimserver_valgrind_log", nrs_path }, nrs_opts)
    require("r.job").start("Server", { nrs_path }, nrs_opts)
    vim.g.R_Nvim_status = 2

    if config.is_windows then require("r.windows").unset_R_home() end

    edit.add_for_deletion(config.tmpdir .. "/run_R_stdout")
    edit.add_for_deletion(config.tmpdir .. "/run_R_stderr")

    vim.api.nvim_create_user_command(
        "RGetNRSInfo",
        require("r.server").request_nrs_info,
        {}
    )
end

-- Check if the exit code of the script that built nvimcom was zero
-- and if the file nvimcom_info seems to be OK (has three lines).
local init_exit = function(_, data, _)
    local cnv_again = 0

    if data == 0 or data == 512 then -- ssh success seems to be 512
        start_rnvimserver()
    elseif data == 71 then
        -- No writable directory to update nvimcom
        -- Avoid redraw of status line while waiting user input in MkRdir()
        b_err = vim.list_extend(b_err, b_warn)
        b_warn = {}
        mk_R_dir()
    elseif data == 72 and not config.is_windows and not pkgbuild_attempt then
        -- R.nvim/nvimcom directory not found. Perhaps R running in remote machine...
        -- Try to use local R to build the nvimcom package.
        pkgbuild_attempt = true
        if vim.fn.executable("R") == 1 then
            local shf = {
                "cd " .. config.tmpdir,
                "R CMD build " .. config.rnvim_home .. "/nvimcom",
            }
            vim.fn.writefile(shf, config.tmpdir .. "/buildpkg.sh")
            local obj = utils
                .system({ "sh", config.tmpdir .. "/buildpkg.sh" }, { text = true })
                :wait()
            if obj.code == 0 then
                M.check_nvimcom_version()
                cnv_again = 1
            end
            vim.fn.delete(config.tmpdir .. "/buildpkg.sh")
        end
    else
        if vim.fn.filereadable(vim.fn.expand("~/.R/Makevars")) == 1 then
            warn(
                "ERROR! Please, run :RDebugInfo for details, and check your '~/.R/Makevars'."
            )
        else
            warn(
                "ERROR: R exit code = "
                    .. tostring(data)
                    .. "! Please, run :RDebugInfo for details."
            )
        end
    end

    edit.add_to_debug_info("before_nrs.R stderr", table.concat(b_err, "\n"))
    edit.add_to_debug_info("before_nrs.R stdout", table.concat(b_out, "\n"))
    b_err = {}
    b_out = {}
    edit.add_for_deletion(config.tmpdir .. "/bo_code.R")
    edit.add_for_deletion(config.localtmpdir .. "/libs_in_nrs_" .. vim.env.RNVIM_ID)
    edit.add_for_deletion(config.tmpdir .. "/libnames_" .. vim.env.RNVIM_ID)
    if #b_warn > 0 then
        local wrn = table.concat(b_warn, "\n")
        edit.add_to_debug_info("RInit Warning", wrn)
        warn(wrn)
    end
    if cnv_again == 0 then
        b_time = (uv.hrtime() - b_time) / 1000000000
        edit.add_to_debug_info("before_nrs.R", b_time, "Time")
    end
end

-- List R libraries from buffer
local list_libs_from_buffer = function()
    local start_libs = config.start_libs or "base,stats,graphics,grDevices,utils,methods"
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    local lib
    local flibs = {}
    for _, v in pairs(lines) do
        if v:find("^%s*library%s*%(") or v:find("^%s*library%s*%(") then
            lib = string.gsub(v, "%s*", "")
            lib = string.gsub(lib, "%s*,.*", "")
            lib = string.gsub(lib, "%s*library%s*%(%s*", "")
            lib = string.gsub(lib, "%s*require%s*%(%s*", "")
            lib = string.gsub(lib, '"', "")
            lib = string.gsub(lib, "'", "")
            lib = string.gsub(lib, "%s*%).*", "")
            table.insert(flibs, lib)
        end
    end
    local libs = ""
    if #start_libs > 4 then libs = '"' .. start_libs:gsub(",", '", "') .. '"' end
    if #flibs > 0 then
        if libs ~= "" then libs = libs .. ", " end
        libs = libs .. '"' .. table.concat(flibs, '", "') .. '"'
    end
    return libs
end

-- Function to handle BAAExit
local baa_exit = function(_, data, _)
    if data == 0 or data == 512 then job.stdin("Server", "41\n") end
end

-- Build all arguments
local build_all_args
build_all_args = function(_)
    if vim.fn.filereadable(config.compldir .. "/args_lock") == 1 then
        vim.fn.timer_start(1000, build_all_args)
        return
    end

    local flist = vim.fn.glob(config.compldir .. "/omnils_*", false, true)
    for i, afile in ipairs(flist) do
        flist[i] = afile:gsub("/omnils_", "/args_")
    end

    local rscrpt = { 'library("nvimcom", warn.conflicts = FALSE)' }
    for _, afile in ipairs(flist) do
        if vim.fn.filereadable(afile) == 0 then
            local pkg = afile:gsub(".*/args_", ""):gsub("_.*", "")
            table.insert(
                rscrpt,
                'nvimcom:::nvim.buildargs("' .. afile .. '", "' .. pkg .. '")'
            )
        end
    end

    if #rscrpt == 1 then return end

    vim.fn.writefile({ "" }, config.compldir .. "/args_lock")
    table.insert(rscrpt, 'unlink("' .. config.compldir .. '/args_lock")')

    local scrptnm = config.tmpdir .. "/build_args.R"
    edit.add_for_deletion(scrptnm)
    vim.fn.writefile(rscrpt, scrptnm)
    if config.remote_compldir then
        scrptnm = config.remote_compldir .. "/tmp/build_args.R"
    end
    local jobh = { on_exit = baa_exit }
    require("r.job").start(
        "Build_args",
        { config.R_cmd, "--quiet", "--no-save", "--no-restore", "--slave", "-f", scrptnm },
        jobh
    )
end

-- Add words to the completion list of :Rhelp
local add_to_Rhelp_list = function(lib)
    local omf = config.compldir .. "/omnils_" .. lib

    -- List of objects
    local olist = vim.fn.readfile(omf)

    -- Library setwidth has no functions
    if #olist == 0 or (#olist == 1 and #olist[1] < 3) then return end

    -- List of objects for :Rhelp completion
    for _, xx in ipairs(olist) do
        local xxx = vim.fn.split(xx, "\006")
        if #xxx > 0 and not string.match(xxx[1], "\\$") then
            table.insert(rhelp_list, xxx[1])
        end
    end
end

-- Filter words for :Rhelp
--- arg string Argument being typed to command.
--- _   string The complete command line, including "Rhelp".
--- _   number Cursor position in complete command line.
M.list_objs = function(arg, _, _)
    local lob = {}
    for _, xx in ipairs(rhelp_list) do
        if xx:sub(1, 1) == arg:sub(1, 1) then table.insert(lob, xx) end
    end
    return lob
end

-- This function is called for the first time before R is running because we
-- support syntax highlighting and omni completion of default libraries' objects.
M.update_Rhelp_list = function()
    if
        vim.fn.filereadable(config.localtmpdir .. "/libs_in_nrs_" .. vim.env.RNVIM_ID)
        == 0
    then
        return
    end

    local libs_in_nrs =
        vim.fn.readfile(config.localtmpdir .. "/libs_in_nrs_" .. vim.env.RNVIM_ID)
    for _, lib in ipairs(libs_in_nrs) do
        add_to_Rhelp_list(lib)
    end
    -- Building args_ files is too time-consuming. Do it asynchronously.
    vim.fn.timer_start(1, build_all_args)
end

M.check_nvimcom_version = function()
    local flines
    local nvimcom_desc_path = config.rnvim_home .. "/nvimcom/DESCRIPTION"

    if vim.fn.filereadable(nvimcom_desc_path) == 1 then
        local ndesc = vim.fn.readfile(nvimcom_desc_path)
        local current = string.gsub(ndesc[2], "Version: ", "")
        flines = { 'needed_nvc_version <- "' .. current .. '"' }
    else
        flines = { "needed_nvc_version <- NULL" }
    end

    local libs = list_libs_from_buffer()
    table.insert(flines, 'nvim_r_home <- "' .. config.rnvim_home .. '"')
    table.insert(flines, "libs <- c(" .. libs .. ")")
    vim.list_extend(flines, vim.fn.readfile(config.rnvim_home .. "/scripts/before_nrs.R"))

    local scrptnm = config.tmpdir .. "/before_nrs.R"
    vim.fn.writefile(flines, scrptnm)
    edit.add_for_deletion(config.tmpdir .. "/before_nrs.R")

    -- Run the script as a job, setting callback functions to receive its
    -- stdout, stderr, and exit code.
    local jobh = {
        on_stdout = init_stdout,
        on_stderr = init_stderr,
        on_exit = init_exit,
    }

    local remote_compldir = config.remote_compldir
    if config.remote_compldir ~= "" then
        scrptnm = remote_compldir .. "/tmp/before_nrs.R"
    end

    b_time = uv.hrtime()
    require("r.job").start(
        "Init R",
        { config.R_cmd, "--quiet", "--no-save", "--no-restore", "--slave", "-f", scrptnm },
        jobh
    )
    edit.add_for_deletion(config.tmpdir .. "/libPaths")
end

-- Get information from rnvimserver (currently only the names of loaded libraries).
M.request_nrs_info = function() job.stdin("Server", "42\n") end

-- Called by rnvimserver when it gets an error running R code
M.show_bol_error = function(stt)
    if vim.fn.filereadable(config.tmpdir .. "/run_R_stderr") == 1 then
        local ferr = table.concat(vim.fn.readfile(config.tmpdir .. "/run_R_stderr"), "\n")
        local errmsg = "Exit status: " .. stt .. "\n" .. ferr
        if
            ferr:find("Error in library..nvimcom...*there is no package called .*nvimcom")
        then
            -- This will happen if the user manually changes .libPaths
            vim.fn.delete(config.compldir .. "/nvimcom_info")
            errmsg = errmsg .. "\nPlease, restart " .. vim.v.progname
        end
        edit.add_to_debug_info("Error running R code", errmsg)
        warn("Error building omnils_ file. Run :RDebugInfo for details.")
        vim.fn.delete(config.tmpdir .. "/run_R_stderr")
    else
        warn(config.tmpdir .. "/run_R_stderr not found")
    end
end

-- Callback function
M.echo_nrs_info = function(info)
    vim.schedule(function() vim.api.nvim_echo({ { info } }, false, {}) end)
end

return M
