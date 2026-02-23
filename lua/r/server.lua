local edit = require("r.edit")
local config = require("r.config").get_config()
local warn = require("r.log").warn
local uv = vim.uv
local b_warn = {}
local b_err = {}
local b_out = {}
local b_time
local o_err = {}
local rhelp_list = {}
local lob = {}
local pkgbuild_attempt = false
local libs_in_rns = ""
local building_objls = false
local check_executable = require("r.utils").check_executable

local M = {}

---@param libd string
local mk_R_dir = function(libd)
    vim.schedule(function()
        vim.ui.input(
            { prompt = '"' .. libd .. '" is not writable. Create it now? [y/n] ' },
            function(input)
                if input and input:find("y") then
                    local dw = vim.fn.mkdir(vim.fn.expand(libd), "p")
                    if dw == 1 then
                        -- Try again
                        M.check_nvimcom_version()
                    else
                        warn('Failed creating "' .. libd .. '"')
                    end
                else
                    vim.schedule(function() vim.api.nvim_echo({ "\n" }, false, {}) end)
                end
            end
        )
    end)
end

---Callback function to process the stdout of before_rns.R
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
        if not rcmd:find("\020") then
            out_line = rcmd
            return
        end
        out_line = ""

        -- In spite of flush(stdout()), rcmd might be concatenating two commands
        local rcmdl = vim.fn.split(rcmd, "\020", false)
        for _, c in ipairs(rcmdl) do
            if c:find("^WARN: ") then
                table.insert(b_warn, c:sub(7))
            elseif c:find("^LIBD: ") then
                mk_R_dir(c:sub(7))
            elseif c:find("^ECHO: ") then
                local msg = c:sub(7)
                vim.schedule(function() vim.api.nvim_echo({ { msg } }, false, {}) end)
            elseif c:find("^INFO: ") then
                local info = vim.fn.split(c:sub(7), "=")
                if #info == 3 then
                    edit.add_to_debug_info(info[1], info[2], info[3])
                else
                    edit.add_to_debug_info(info[1], info[2])
                end
            end
        end
    else
        if not building_objls then table.insert(b_out, rcmd) end
    end
end

local init_stderr = function(_, data, _)
    if data then
        local s = table.concat(data, "")
        s = string.gsub(s, "\r", "")
        if building_objls then
            table.insert(o_err, s)
        else
            table.insert(b_err, s)
        end
    end
end

---Find the path to the rnvimserver executable in the specified library directory.
---@param libdir string
---@return string
local find_rns_path = function(libdir)
    local rns
    if config.is_windows then
        rns = "rnvimserver.exe"
    else
        rns = "rnvimserver"
    end
    local paths = {
        libdir .. "/bin/" .. rns,
        libdir .. "/bin/x64/" .. rns,
        libdir .. "/bin/i386/" .. rns,
    }
    for _, path in ipairs(paths) do
        if vim.fn.filereadable(path) == 1 then return path end
    end
    warn('Application "' .. rns .. '" not found at "' .. libdir .. '"')
    return ""
end

-- Check and set some variables and, finally, start the rnvimserver
local start_rnvimserver = function()
    if vim.g.R_Nvim_status > 1 then return end

    local rns_path

    if config.local_R_library_dir ~= "" then
        rns_path = find_rns_path(config.local_R_library_dir .. "/nvimcom")
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
                rns_path = find_rns_path(info[2])
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

    local rns_dir = rns_path:gsub("/rnvimserver.*", "")

    -- Some pdf viewers run rnvimserver to send SyncTeX messages back to Neovim
    if config.is_windows then
        vim.env.PATH = rns_dir .. ";" .. vim.env.PATH
    else
        vim.env.PATH = rns_dir .. ":" .. vim.env.PATH
    end

    -- Options in the rnvimserver application are set through environment variables
    local rns_env = {}
    if config.objbr_opendf then rns_env.RNVIM_OPENDF = "TRUE" end
    if config.objbr_openlist then rns_env.RNVIM_OPENLS = "TRUE" end
    if config.objbr_allnames then rns_env.RNVIM_OBJBR_ALLNAMES = "TRUE" end
    rns_env.RNVIM_RPATH = config.R_cmd
    rns_env.RNVIM_LOCAL_TMPDIR = config.localtmpdir
    rns_env.RNVIM_MAX_DEPTH = tostring(config.compl_data.max_depth)
    local disable_parts = {}
    if not config.r_ls.completion then table.insert(disable_parts, "completion") end
    if not config.r_ls.signature then table.insert(disable_parts, "signature") end
    if not config.r_ls.hover then table.insert(disable_parts, "hover") end
    if not config.r_ls.definition then table.insert(disable_parts, "definition") end
    if not config.r_ls.references then table.insert(disable_parts, "references") end
    if not config.r_ls.implementation then
        table.insert(disable_parts, "implementation")
    end
    local disable = table.concat(disable_parts)
    rns_env.R_LS_DISABLE = disable

    -- We have to set R's home directory on Windows because rnvimserver will
    -- run R to build the list for auto completion.
    if config.is_windows then require("r.windows").set_R_home() end

    vim.g.R_Nvim_status = 2
    require("r.lsp").start(rns_path:match(".*/(.*)"), rns_env)

    if config.is_windows then require("r.windows").unset_R_home() end

    edit.add_for_deletion(config.tmpdir .. "/run_R_stdout")
    edit.add_for_deletion(config.tmpdir .. "/run_R_stderr")

    vim.api.nvim_create_user_command("RGetNRSInfo", require("r.server").echo_rns_info, {})
end

-- Function to build the package
local function build_package()
    -- Change directory to config.tmpdir
    local cmd = "cd "
        .. vim.fn.shellescape(config.tmpdir)
        .. " && "
        .. vim.fn.shellescape("R")
        .. " CMD build "
        .. vim.fn.shellescape(config.rnvim_home .. "/nvimcom")

    uv.spawn("sh", {
        args = { "-c", cmd },
        stdio = nil,
    }, function(code)
        if code == 0 then
            M.check_nvimcom_version()
        else
            warn("Failed to build the package.")
        end
    end)
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
    elseif data == 72 and not config.is_windows and not pkgbuild_attempt then
        -- R.nvim/nvimcom directory not found. Perhaps R running in remote machine...
        -- Try to use local R to build the nvimcom package.
        pkgbuild_attempt = true
        check_executable("R", function(exists)
            if exists then
                build_package()
            else
                warn('"R" executable not found.')
            end
        end)
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

    edit.add_to_debug_info("before_rns.R stderr", table.concat(b_err, "\n"))
    edit.add_to_debug_info("before_rns.R stdout", table.concat(b_out, "\n"))
    b_err = {}
    b_out = {}
    edit.add_for_deletion(config.tmpdir .. "/bo_code.R")
    edit.add_for_deletion(config.tmpdir .. "/libnames_" .. vim.env.RNVIM_ID)
    if #b_warn > 0 then
        local wrn = table.concat(b_warn, "\n")
        edit.add_to_debug_info("RInit Warning", wrn)
        warn(wrn)
    end
    if cnv_again == 0 then
        b_time = (uv.hrtime() - b_time) / 1000000000
        edit.add_to_debug_info("before_rns.R (async)", b_time, "Time")
    end
end

local build_objls_exit = function()
    vim.schedule(function() vim.api.nvim_echo({ { " " } }, false, {}) end)
    edit.add_to_debug_info(
        "stderr of last completion data building",
        table.concat(o_err, "\n")
    )
    building_objls = false
    require("r.lsp").send_msg({ code = "41" })
end

-- List R libraries from buffer
local list_libs_from_buffer = function()
    local start_libs = config.start_libs or "base,stats,graphics,grDevices,utils,methods"
    start_libs = string.gsub(start_libs, " ", "")
    local flibs = vim.split(start_libs, ",")

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    for _, v in pairs(lines) do
        if v:find("^%s*library%s*%(") or v:find("^%s*require%s*%(") then
            local lib = string.gsub(v, "%s*", "")
            lib = string.gsub(lib, "%s*,.*", "")
            lib = string.gsub(lib, "%s*library%s*%(%s*", "")
            lib = string.gsub(lib, "%s*require%s*%(%s*", "")
            lib = string.gsub(lib, '"', "")
            lib = string.gsub(lib, "'", "")
            lib = string.gsub(lib, "%s*%).*", "")
            table.insert(flibs, lib)
        end
    end
    local libs = table.concat(flibs, ",") .. "#"
    vim.fn.writefile({ libs }, config.tmpdir .. "/libnames_" .. vim.env.RNVIM_ID)
end

-- Add words to the completion list of :Rhelp
local fill_Rhelp_list = function()
    libs_in_rns = string.gsub(libs_in_rns, " *$", "")
    local libs = vim.split(libs_in_rns, ",", { trimempty = true })
    libs_in_rns = ""
    M.rhelp_list = {}

    for _, v in pairs(libs) do
        local omf = config.compldir .. "/alias_" .. v

        -- List of objects
        local olist = vim.fn.readfile(omf)

        -- Some libraries have no functions
        if #olist > 0 then
            -- List of objects for :Rhelp completion
            for k, xx in ipairs(olist) do
                if k > 1 then
                    local xxx = vim.fn.split(xx, "\006")
                    if #xxx == 2 then table.insert(rhelp_list, xxx[2]) end
                end
            end
        end
    end
end

-- Filter words for :Rhelp
--- arg string Argument being typed to command.
--- _   string The complete command line, including "Rhelp".
--- _   number Cursor position in complete command line.
M.list_objs = function(arg, _, _)
    if arg == "" then return rhelp_list end
    if libs_in_rns ~= "" then fill_Rhelp_list() end
    lob = {}
    for _, xx in ipairs(rhelp_list) do
        if xx:find(arg, 1, true) then table.insert(lob, xx) end
    end
    return lob
end

---This function is called for the first time before R is running because we
---support auto completion of default libraries' objects.
---@param libnames string
M.update_Rhelp_list = function(libnames)
    libs_in_rns = libnames
    if
        vim.g.R_Nvim_status == 3
        and (
            config.auto_start:find("always")
            or (config.auto_start:find("startup") and vim.api.nvim_get_current_buf() == 1)
        )
    then
        require("r.run").start_R("R")
    end
end

M.check_nvimcom_version = function()
    list_libs_from_buffer()

    local flines
    local nvimcom_desc_path = config.rnvim_home .. "/nvimcom/DESCRIPTION"

    if vim.fn.filereadable(nvimcom_desc_path) == 1 then
        local ndesc = vim.fn.readfile(nvimcom_desc_path)
        local current = string.gsub(ndesc[2], "Version: ", "")
        flines = { 'needed_nvc_version <- "' .. current .. '"' }
    else
        flines = { "needed_nvc_version <- NULL" }
    end

    table.insert(flines, 'nvim_r_home <- "' .. config.rnvim_home .. '"')
    vim.list_extend(
        flines,
        vim.fn.readfile(config.rnvim_home .. "/resources/before_rns.R")
    )

    local scrptnm = config.tmpdir .. "/before_rns.R"
    vim.fn.writefile(flines, scrptnm)
    edit.add_for_deletion(config.tmpdir .. "/before_rns.R")

    -- Run the script as a job, setting callback functions to receive its
    -- stdout, stderr, and exit code.
    local jobh = {
        on_stdout = init_stdout,
        on_stderr = init_stderr,
        on_exit = init_exit,
    }

    local remote_compldir = config.remote_compldir
    if config.remote_compldir ~= "" then
        scrptnm = remote_compldir .. "/tmp/before_rns.R"
    end

    b_time = uv.hrtime()
    require("r.job").start(
        "Init R",
        { config.R_cmd, "--quiet", "--no-save", "--no-restore", "--slave", "-f", scrptnm },
        jobh
    )
end

--- Build objls_ files
M.build_cache_files = function()
    if vim.g.R_Nvim_status < 3 then vim.g.R_Nvim_status = 3 end
    local Rcode = {
        "library('nvimcom', character.only = TRUE, warn.conflicts = FALSE,",
        "  verbose = FALSE, quietly = TRUE, mask.ok = 'vi')",
        "nvimcom:::nvim.build.cmplls()",
    }
    local scrptnm = config.tmpdir .. "/bo_code.R"
    vim.fn.writefile(Rcode, scrptnm)
    local opts = {
        on_stdout = init_stdout,
        on_stderr = init_stderr,
        on_exit = build_objls_exit,
    }

    building_objls = true
    require("r.job").start(
        "Build completion data",
        { config.R_cmd, "--quiet", "--no-save", "--no-restore", "--slave", "-f", scrptnm },
        opts
    )
end

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
        warn("Error building objls_ file. Run :RDebugInfo for details.")
        vim.fn.delete(config.tmpdir .. "/run_R_stderr")
    else
        warn(config.tmpdir .. "/run_R_stderr not found")
    end
end

M.echo_rns_info = function()
    local tbl = { { "Loaded libraries", "Title" }, { ":\n" } }
    local lines = vim.split(libs_in_rns, ",")
    for _, v in pairs(lines) do
        table.insert(tbl, { "  " .. v .. "\n" })
    end
    vim.schedule(function() vim.api.nvim_echo(tbl, false, {}) end)
end

return M
