local warn = require("r.log").warn
local utils = require("r.utils")
local uv = vim.uv

-- stylua: ignore start

local config = {
    OutDec              = ".",
    RStudio_cmd         = "",
    R_app               = "R",
    R_args              = {},
    R_cmd               = "R",
    R_path              = "",
    Rout_more_colors    = false,
    applescript         = false,
    arrange_windows     = true,
    assignment_keymap   = "<M-->",
    pipe_keymap         = "<localleader>,",
    pipe_version        = "native",
    auto_scroll         = true,
    auto_start          = "no",
    auto_quit           = false,
    bracketed_paste     = false,
    buffer_opts         = "winfixwidth winfixheight nobuflisted",
    clear_console       = true,
    clear_line          = false,
    close_term          = true,
    convert_range_int   = false,
    compldir            = "",
    compl_data          = {
        max_depth = 3,
        max_size = 1000000,
        max_time = 100,
    },
    config_tmux         = true,
    csv_app             = "",
    disable_cmds        = { "" },
    editing_mode        = "",
    esc_term            = true,
    external_term       = false, -- might be a string
    has_X_tools         = false,
    help_w              = 46,
    hl_term             = true,
    hook                = {
                              on_filetype = function() end,
                              after_config = function() end,
                              after_R_start = function() end,
                              after_ob_open = function() end,
                          },
    insert_mode_cmds    = false,
    latexcmd            = { "default" },
    listmethods         = false,
    local_R_library_dir = "",
    max_paste_lines     = 20,
    min_editor_width    = 80,
    non_r_compl         = true,
    setwd               = "no",
    nvimpager           = "split_h",
    objbr_allnames      = false,
    objbr_auto_start    = false,
    objbr_h             = 10,
    objbr_opendf        = true,
    objbr_openlist      = false,
    objbr_place         = "script,right",
    objbr_w             = 40,
    objbr_mappings      = {
                              s = "summary",
                              p = "plot",
                          },
    objbr_placeholder   = "{object}",
    open_example        = true,
    open_html           = "open and focus",
    open_pdf            = "open and focus",
    paragraph_begin     = true,
    parenblock          = true,
    path_split_fun      = "file.path",
    pdfviewer           = "",
    quarto_preview_args = "",
    quarto_render_args  = "",
    rconsole_height     = 15,
    rconsole_width      = 80,
    register_treesitter = true,
    remote_compldir     = "",
    rm_knit_cache       = false,
    rmarkdown_args      = "",
    rmd_environment     = ".GlobalEnv",
    rmdchunk            = 2, -- might be a string
    rmhidden            = false,
    rnowebchunk         = true,
    rnvim_home          = "",
    routnotab           = false,
    rproj_prioritise    = {
                               "pipe_version"
                          },
    save_win_pos        = true,
    set_home_env        = true,
    setwidth            = 2,
    silent_term         = false,
    skim_app_path       = "",
    source_args         = "",
    specialplot         = false,
    start_libs          = "base,stats,graphics,grDevices,utils,methods",
    synctex             = true,
    term_pid            = 0,
    term_title          = "term",
    texerr              = true,
    tmpdir              = "",
    user_login          = "",
    user_maps_only      = false,
    wait                = 60,
}

-- stylua: ignore end

local user_opts = {}
local did_real_setup = false

local set_editing_mode = function()
    if config.editing_mode ~= "" then return end

    local em = "emacs"
    local iprc = tostring(vim.fn.expand("~/.inputrc"))
    if vim.fn.filereadable(iprc) == 1 then
        local inputrc = vim.fn.readfile(iprc)
        local line
        local e
        for _, v in pairs(inputrc) do
            line = string.gsub(v, "^%s*#.*", "")
            _, e = string.find(line, "set%s+editing%-mode")
            if e then
                em = string.gsub(line, ".+editing%-mode%s+", "")
                em = string.gsub(em, "%s*", "")
            end
        end
    end
    config.editing_mode = em
end

local set_pdf_viewer = function()
    if config.is_darwin then
        config.pdfviewer = "skim"
    elseif config.is_windows then
        config.pdfviewer = "sumatra"
    else
        config.pdfviewer = "zathura"
    end
end

--- Edit the module config to include options set by the user
---
--- This happens recursively through sub-tables. I.e. if the global config
--- is config = { a = 1, b = { c = 2, d = 3 } }, and we have
--- user_config = { b = { d = 4 } }, the end result will be
--- final_config = { a = 1, b = { c = 2, d = 4 } }.
---
--- The key names, types and values of user options are all checked before
--- being applied. If a check fails, a warning is show, and the default option
--- is used instead.
local apply_user_opts = function()
    -- Ensure that some config options will be in lower case
    for _, v in pairs({
        "auto_start",
        "editing_mode",
        "nvimpager",
        "open_pdf",
        "open_html",
        "setwd",
    }) do
        if user_opts[v] then user_opts[v] = string.lower(user_opts[v]) end
    end

    -- stylua: ignore start
    -- If an option can be multiple types, you can specify those types here.
    -- Otherwise, the user option is checked against the type of the default
    -- value.
    local valid_types = {
        external_term    = { "boolean", "string" },
        rmdchunk         = { "number", "string" },
        csv_app          = { "string", "function" },
    }

    -- If an option is an enum, you can define the possible values here:
    local valid_values = {
        auto_start       = { "no", "on startup", "always" },
        editing_mode     = { "vi", "emacs" },
        nvimpager        = { "no", "tab", "split_h", "split_v", "float" },
        open_html        = { "no", "open", "open and focus" },
        open_pdf         = { "no", "open", "open and focus" },
        setwd            = { "no", "file", "nvim" },
        pipe_version     = { "native", "magrittr" },
        path_split_fun   = { "here::here", "here", "file.path", "fs::path", "path" },
    }
    -- stylua: ignore end

    ---@param user_opt any An option or table of options supplied by the user
    ---@param key table The position of `user_opt` in `config`. E.g. if
    --- `user_opt` is `hook.on_filetype` then `key` will be `{ "hook", "on_filetype" }`
    local function apply(user_opt, key)
        local key_name = table.concat(key, ".")

        -- Get the default value for the option (might be in a nested table)
        local default_val = config
        local config_chunk = config
        for _, k in pairs(key) do
            config_chunk = default_val
            if type(default_val) == "table" then
                default_val = default_val[k]
            else
                default_val = nil
                break
            end
        end

        -----------------------------------------------------------------------
        -- 1. Check the option exists
        -----------------------------------------------------------------------
        if default_val == nil then
            warn("Invalid option `" .. key_name .. "`.")
            return
        end

        -----------------------------------------------------------------------
        -- 2. Check the option has one of the expected types
        -----------------------------------------------------------------------
        local expected_types = valid_types[key_name] or { type(default_val) }
        if vim.fn.index(expected_types, type(user_opt)) == -1 then
            warn(
                "Invalid option type for `"
                    .. key_name
                    .. "`. Type should be "
                    .. utils.msg_join(expected_types, ", ", ", or ", "")
                    .. ", not "
                    .. type(user_opt)
                    .. "."
            )
            return
        end

        -----------------------------------------------------------------------
        -- 3. Check the option has one of the expected values
        -----------------------------------------------------------------------
        local expected_values = valid_values[key_name]
        if expected_values and vim.fn.index(expected_values, user_opt) == -1 then
            warn(
                "Invalid option value for `"
                    .. key_name
                    .. "`. Value should be "
                    .. utils.msg_join(expected_values, ", ", ", or ")
                    .. ', not "'
                    .. user_opt
                    .. '".'
            )
            return
        end

        -----------------------------------------------------------------------
        -- 4. If the option is a dictionary, check each value individually
        -----------------------------------------------------------------------
        if type(user_opt) == "table" and key_name ~= "objbr_mappings" then
            for k, v in pairs(user_opt) do
                if type(k) == "string" then
                    local next_key = {}
                    for _, kk in pairs(key) do
                        table.insert(next_key, kk)
                    end
                    table.insert(next_key, k)
                    apply(v, next_key)
                end
            end
            return
        end

        -----------------------------------------------------------------------
        -- 5. Update the value in the module `config`
        -----------------------------------------------------------------------
        config_chunk[key[#key]] = user_opt
    end

    apply(user_opts, {})
end

local do_common_global = function()
    config.uname = uv.os_uname().sysname
    config.is_windows = config.uname:find("Windows", 1, true) ~= nil
    config.is_darwin = config.uname == "Darwin"

    -- config.rnvim_home should be the directory where the plugin files are.
    config.rnvim_home = vim.fn.expand("<script>:h:h")

    -- config.uservimfiles must be a writable directory. It will be config.rnvim_home
    -- unless it's not writable. Then it wil be ~/.vim or ~/vimfiles.
    if vim.fn.filewritable(config.rnvim_home) == 2 then
        config.uservimfiles = config.rnvim_home
    else
        config.uservimfiles = vim.split(vim.fn.expand("&runtimepath"), ",")[1]
    end

    -- Windows logins can include domain, e.g: 'DOMAIN\Username', need to remove
    -- the backslash from this as otherwise cause file path problems.
    if config.user_login == "" then
        if vim.env.LOGNAME then
            config.user_login = vim.fn.escape(vim.env.LOGNAME, "\\"):gsub("\\", "")
        elseif vim.env.USER then
            config.user_login = vim.fn.escape(vim.env.USER, "\\"):gsub("\\", "")
        elseif vim.env.USERNAME then
            config.user_login = vim.fn.escape(vim.env.USERNAME, "\\"):gsub("\\", "")
        elseif vim.env.HOME then
            config.user_login = vim.fn.escape(vim.env.HOME, "\\"):gsub("\\", "")
        elseif vim.fn.executable("whoami") ~= 0 then
            config.user_login = vim.fn.system("whoami")
        else
            config.user_login = "NoLoginName"
            warn("Could not determine user name.")
        end
    end

    config.user_login = config.user_login:gsub(".*\\", "")
    config.user_login = config.user_login:gsub("[^%w]", "")
    if config.user_login == "" then
        config.user_login = "NoLoginName"
        warn("Could not determine user name.")
    end

    if config.is_windows then
        config.rnvim_home = utils.normalize_windows_path(config.rnvim_home)
        config.uservimfiles = utils.normalize_windows_path(config.uservimfiles)
    end

    if config.compldir ~= "" then
        config.compldir = vim.fn.expand(config.compldir)
    elseif config.is_windows and vim.env.APPDATA then
        config.compldir = vim.fn.expand(vim.env.APPDATA) .. "\\R.nvim"
    elseif vim.env.XDG_CACHE_HOME then
        config.compldir = vim.fn.expand(vim.env.XDG_CACHE_HOME) .. "/R.nvim"
    elseif vim.fn.isdirectory(vim.fn.expand("~/.cache")) ~= 0 then
        config.compldir = vim.fn.expand("~/.cache/R.nvim")
    elseif vim.fn.isdirectory(vim.fn.expand("~/Library/Caches")) ~= 0 then
        config.compldir = vim.fn.expand("~/Library/Caches/R.nvim")
    else
        config.compldir = config.uservimfiles .. "/R_cache/"
    end

    utils.ensure_directory_exists(config.compldir)

    -- Create or update the README (objls_ files will be regenerated if older than
    -- the README).
    local need_readme = false
    local first_line = "Last change in this file: 2024-08-15"
    if
        vim.fn.filereadable(config.compldir .. "/README") == 0
        or vim.fn.readfile(config.compldir .. "/README")[1] ~= first_line
    then
        need_readme = true
    end

    if need_readme then
        local l = vim.fn.split(vim.fn.glob(config.compldir .. "/*"), "\n")
        if #l > 0 then
            for _, f in ipairs(l) do
                vim.fn.delete(f)
            end
        end

        local readme = {
            first_line,
            "",
            "DON'T SAVE FILES IN THIS DIRECTORY. All files in this directory are",
            "automatically deleted when there is a change in the data format required",
            "by R.nvim.",
            "",
            "The files in this directory were generated by R.nvim automatically:",
            "The objls_, args_, and alias_ files, and inst_libs are used for auto",
            "completion and to fill the Object Browser. They will be regenerated if you",
            "either delete them or delete this README file.",
            "",
            "When you load a new version of a library, their files are replaced.",
            "",
            "Files corresponding to uninstalled libraries are not automatically deleted.",
            "You should manually delete them if you want to save disk space.",
            "",
            "All lines in the objls_ files have 7 fields with information on the object",
            "separated by the byte \\006:",
            "",
            "  1. Name.",
            "",
            "  2. Single character representing the type of object (look at the function",
            "     nvimcom_glbnv_line at nvimcom/src/nvimcom.c to know the meaning of the",
            "     characters).",
            "",
            "  3. Class.",
            "",
            "  4. Either the package or the environment of the object.",
            "",
            "  5. If the object is a function, the list of arguments.",
            "",
            "  6. Short description.",
            "",
            "  7. Long description.",
            "",
            "Notes:",
            "",
            "  - There is a final \\006 at the end of the line.",
            "",
            "  - Backslashes are replaced with the byte \\x12.",
            "",
            "  - Single quotes are replaced with the byte \\x13.",
            "",
            "  - Line breaks are indicated by \\x14.",
        }

        vim.fn.writefile(readme, config.compldir .. "/README")
    end

    -- Check if the 'config' table has the key 'tmpdir'
    if not config.tmpdir ~= "" then
        -- Set temporary directory based on the platform
        if config.is_windows then
            if vim.env.TMP and vim.fn.isdirectory(vim.env.TMP) ~= 0 then
                config.tmpdir = vim.env.TMP .. "/R.nvim-" .. config.user_login
            elseif vim.env.TEMP and vim.fn.isdirectory(vim.env.TEMP) ~= 0 then
                config.tmpdir = vim.env.TEMP .. "/R.nvim-" .. config.user_login
            else
                config.tmpdir = config.uservimfiles .. "/R_tmp"
            end
            config.tmpdir = utils.normalize_windows_path(config.tmpdir)
        else
            if vim.env.TMPDIR and vim.fn.isdirectory(vim.env.TMPDIR) ~= 0 then
                if string.find(vim.env.TMPDIR, "/$") then
                    config.tmpdir = vim.env.TMPDIR .. "R.nvim-" .. config.user_login
                else
                    config.tmpdir = vim.env.TMPDIR .. "/R.nvim-" .. config.user_login
                end
            elseif vim.fn.isdirectory("/dev/shm") ~= 0 then
                config.tmpdir = "/dev/shm/R.nvim-" .. config.user_login
            elseif vim.fn.isdirectory("/tmp") ~= 0 then
                config.tmpdir = "/tmp/R.nvim-" .. config.user_login
            else
                config.tmpdir = config.uservimfiles .. "/R_tmp"
            end
        end
    end

    -- Adjust options when accessing R remotely
    config.localtmpdir = config.tmpdir
    if config.remote_compldir ~= "" then
        vim.env.RNVIM_REMOTE_COMPLDIR = config.remote_compldir
        vim.env.RNVIM_REMOTE_TMPDIR = config.remote_compldir .. "/tmp"
        config.tmpdir = config.compldir .. "/tmp"
    else
        vim.env.RNVIM_REMOTE_COMPLDIR = config.compldir
        vim.env.RNVIM_REMOTE_TMPDIR = config.tmpdir
    end

    utils.ensure_directory_exists(config.tmpdir)
    utils.ensure_directory_exists(config.localtmpdir)

    vim.env.RNVIM_TMPDIR = config.tmpdir
    vim.env.RNVIM_COMPLDIR = config.compldir

    -- Make the file name of files to be sourced
    if config.remote_compldir ~= "" then
        config.source_read = config.remote_compldir .. "/tmp/Rsource-" .. vim.fn.getpid()
    else
        config.source_read = config.tmpdir .. "/Rsource-" .. vim.fn.getpid()
    end
    config.source_write = config.tmpdir .. "/Rsource-" .. vim.fn.getpid()

    -- Default values of some variables
    if
        config.RStudio_cmd ~= ""
        or (
            config.is_windows
            and type(config.external_term) == "boolean"
            and config.external_term == true
        )
    then
        -- Sending multiple lines at once to either Rgui on Windows or RStudio does not work.
        config.max_paste_lines = 1
        config.bracketed_paste = false
        config.parenblock = false
    end

    if type(config.external_term) == "boolean" and config.external_term == false then
        config.nvimpager = "split_h"
        config.save_win_pos = false
        config.arrange_windows = false
    else
        config.nvimpager = "tab"
        config.objbr_place = string.gsub(config.objbr_place, "console", "script")
        config.hl_term = false
    end

    if config.R_app:find("radian") then config.hl_term = false end

    if config.is_windows then
        config.save_win_pos = true
        config.arrange_windows = true
    else
        config.save_win_pos = false
        config.arrange_windows = false
    end

    -- The environment variables RNVIM_COMPLCB and RNVIM_COMPLInfo must be defined
    -- before starting the rnvimserver because it needs them at startup.
    vim.env.RNVIM_COMPL_CB = "require('cmp_r').complete_cb"
    vim.env.RNVIM_RSLV_CB = "require('cmp_r').resolve_cb"

    -- Look for invalid options
    local objbrplace = vim.split(config.objbr_place, ",")
    if #objbrplace > 2 then warn("Too many options for R_objbr_place.") end
    for _, pos in ipairs(objbrplace) do
        if
            pos ~= "console"
            and pos ~= "script"
            and pos:lower() ~= "left"
            and pos:lower() ~= "right"
            and pos:lower() ~= "above"
            and pos:lower() ~= "below"
            and pos:lower() ~= "top"
            and pos:lower() ~= "bottom"
        then
            warn(
                'Invalid value for R_objbr_place: "'
                    .. pos
                    .. "\". Please see R.nvim's documentation."
            )
        end
    end

    -- Check if default mean of communication with R is OK

    -- Minimum width for the Object Browser
    if config.objbr_w < 10 then config.objbr_w = 10 end

    -- Minimum height for the Object Browser
    if config.objbr_h < 4 then config.objbr_h = 4 end

    vim.cmd("autocmd BufEnter * lua require('r.edit').buf_enter()")
    vim.cmd("autocmd VimLeave * lua require('r.edit').vim_leave()")

    if vim.v.windowid ~= 0 and not vim.env.WINDOWID then
        vim.env.WINDOWID = vim.v.windowid
    end

    -- Current view of the object browser: .GlobalEnv X loaded libraries
    config.curview = "None"

    -- Set the name of R executable
    if config.is_windows then
        if type(config.external_term) == "boolean" and config.external_term == false then
            config.R_app = "Rterm.exe"
        else
            config.R_app = "Rgui.exe"
        end
        config.R_cmd = "R.exe"
    end

    -- Set security variables
    vim.env.RNVIM_ID = vim.fn.rand(vim.fn.srand())
    vim.env.RNVIM_SECRET = vim.fn.rand()

    -- Avoid problems if either R_rconsole_width or R_rconsole_height is a float number
    -- (https://github.com/jalvesaq/Nvim-R/issues/751#issuecomment-1742784447).
    if type(config.rconsole_width) == "number" then
        config.rconsole_width = math.floor(config.rconsole_width)
    end
    if type(config.rconsole_height) == "number" then
        config.rconsole_height = math.floor(config.rconsole_height)
    end
end

local windows_config = function()
    local wtime = uv.hrtime()
    local isi386 = false

    if config.R_path ~= "" then
        local rpath = vim.split(config.R_path, ";")
        utils.resolve_fullpaths(rpath)
        vim.fn.reverse(rpath)
        for _, dir in ipairs(rpath) do
            if vim.fn.isdirectory(dir) then
                vim.env.PATH = dir .. ";" .. vim.env.PATH
            else
                warn(
                    '"'
                        .. dir
                        .. '" is not a directory. Fix the value of R_path in your config.'
                )
            end
        end
    else
        if vim.env.RTOOLS40_HOME then
            if vim.fn.isdirectory(vim.env.RTOOLS40_HOME .. "\\mingw64\\bin\\") then
                vim.env.PATH = vim.env.RTOOLS40_HOME .. "\\mingw64\\bin;" .. vim.env.PATH
            elseif vim.fn.isdirectory(vim.env.RTOOLS40_HOME .. "\\usr\\bin") then
                vim.env.PATH = vim.env.RTOOLS40_HOME .. "\\usr\\bin;" .. vim.env.PATH
            end
        else
            if vim.fn.isdirectory("C:\\rtools40\\mingw64\\bin") then
                vim.env.PATH = "C:\\rtools40\\mingw64\\bin;" .. vim.env.PATH
            elseif vim.fn.isdirectory("C:\\rtools40\\usr\\bin") then
                vim.env.PATH = "C:\\rtools40\\usr\\bin;" .. vim.env.PATH
            end
        end

        local get_rip = function(run_cmd)
            local resp = utils.system(run_cmd, { text = true }):wait()
            local rout = vim.split(resp.stdout, "\n")
            local rip = {}
            for _, v in pairs(rout) do
                if v:find("InstallPath.*REG_SZ") then table.insert(rip, v) end
            end
            return rip
        end

        -- Check both HKCU and HKLM. See #223
        local reg_roots = { "HKCU", "HKLM" }
        local rip = {}
        for i = 1, #reg_roots do
            if #rip == 0 then
                local run_cmd =
                    { "reg.exe", "QUERY", reg_roots[i] .. "\\SOFTWARE\\R-core\\R", "/s" }
                rip = get_rip(run_cmd)

                if #rip == 0 then
                    -- Normally, 32 bit applications access only 32 bit registry and...
                    -- We have to try again if the user has installed R only in the other architecture.
                    if vim.fn.has("win64") then
                        table.insert(run_cmd, "/reg:64")
                    else
                        table.insert(run_cmd, "/reg:32")
                    end
                    rip = get_rip(run_cmd)

                    if #rip == 0 and i == #reg_roots then
                        warn(
                            "Could not find R path in Windows Registry. "
                                .. "If you have already installed R, please, set the value of 'R_path'."
                        )
                        wtime = (uv.hrtime() - wtime) / 1000000000
                        require("r.edit").add_to_debug_info(
                            "windows setup",
                            wtime,
                            "Time"
                        )
                        return
                    end
                end
            end
        end

        local rinstallpath = nil
        rinstallpath = rip[1]
        rinstallpath = rinstallpath:gsub(".*InstallPath.*REG_SZ%s*", "")
        rinstallpath = rinstallpath:gsub("\n", "")
        rinstallpath = rinstallpath:gsub("%s*$", "")
        local hasR32 = vim.fn.isdirectory(rinstallpath .. "\\bin\\i386")
        local hasR64 = vim.fn.isdirectory(rinstallpath .. "\\bin\\x64")
        if hasR32 == 1 and hasR64 == 0 then isi386 = true end
        if hasR64 == 1 and hasR32 == 0 then isi386 = false end
        if hasR32 == 1 and isi386 then
            vim.env.PATH = rinstallpath .. "\\bin\\i386;" .. vim.env.PATH
        elseif hasR64 == 1 and not isi386 then
            vim.env.PATH = rinstallpath .. "\\bin\\x64;" .. vim.env.PATH
        else
            vim.env.PATH = rinstallpath .. "\\bin;" .. vim.env.PATH
        end
    end

    if not config.R_args then
        if type(config.external_term) == "boolean" and config.external_term == false then
            config.R_args = { "--no-save" }
        else
            config.R_args = { "--sdi", "--no-save" }
        end
    end
    wtime = (uv.hrtime() - wtime) / 1000000000
    require("r.edit").add_to_debug_info("windows setup", wtime, "Time")
end

local tmux_config = function()
    local ttime = uv.hrtime()
    -- Check whether Tmux is OK
    if vim.fn.executable("tmux") == 0 then
        config.external_term = false
        warn("tmux executable not found")
        return
    end

    local tmuxversion
    if config.uname:find("OpenBSD") then
        -- Tmux does not have -V option on OpenBSD: https://github.com/jcfaria/Vim-R-plugin/issues/200
        tmuxversion = "0.0"
    else
        tmuxversion = vim.fn.system("tmux -V")
        if tmuxversion then
            tmuxversion = tmuxversion:gsub(".* ([0-9]%.[0-9]).*", "%1")
            if #tmuxversion ~= 3 then tmuxversion = "1.0" end
            if tmuxversion < "3.0" then warn("R.nvim requires Tmux >= 3.0") end
        end
    end
    ttime = (uv.hrtime() - ttime) / 1000000000
    require("r.edit").add_to_debug_info("tmux setup", ttime, "Time")
end

local unix_config = function()
    local utime = uv.hrtime()
    if config.R_path ~= "" then
        local rpath = vim.split(config.R_path, ":")
        utils.resolve_fullpaths(rpath)

        -- Add the current directory to the beginning of the path
        table.insert(rpath, 1, "")

        -- loop over rpath in reverse.
        for i = #rpath, 1, -1 do
            local dir = rpath[i]
            local is_dir = uv.fs_stat(dir)
            -- Each element in rpath must exist and be a directory
            if is_dir and is_dir.type == "directory" then
                vim.env.PATH = dir .. ":" .. vim.env.PATH
            else
                warn(
                    '"'
                        .. dir
                        .. '" is not a directory. Fix the value of R_path in your config.'
                )
            end
        end
    end

    utils.check_executable(config.R_app, function(exists)
        if not exists then
            warn(
                '"'
                    .. config.R_app
                    .. '" not found. Fix the value of either R_path or R_app in your config.'
            )
        end
    end)

    if
        (type(config.external_term) == "boolean" and config.external_term)
        or type(config.external_term) == "string"
    then
        tmux_config() -- Consider removing this line if it's not necessary
    end
    utime = (uv.hrtime() - utime) / 1000000000
    require("r.edit").add_to_debug_info("unix setup", utime, "Time")
end

local global_setup = function()
    local gtime = uv.hrtime()

    if vim.g.R_Nvim_status == 0 then vim.g.R_Nvim_status = 1 end

    set_pdf_viewer()
    apply_user_opts()

    -- Config values that depend on either system features or other config
    -- values.
    set_editing_mode()

    if type(config.external_term) == "boolean" and config.external_term == false then
        config.auto_quit = true
    end

    -- Load functions that were not converted to Lua yet
    -- Configure more values that depend on either system features or other
    -- config values.
    -- Fix some invalid values
    -- Calls to system() and executable() must run
    -- asynchronously to avoid slow startup on macOS.
    -- See https://github.com/jalvesaq/Nvim-R/issues/625
    do_common_global()
    if config.is_windows then
        windows_config()
    else
        unix_config()
    end

    -- Override default config values with user options for the second time.
    for k, v in pairs(user_opts) do
        config[k] = v
    end

    require("r.commands").create_user_commands()
    vim.fn.timer_start(1, require("r.config").check_health)
    vim.schedule(function() require("r.server").check_nvimcom_version() end)

    if config.hook.after_config then
        vim.schedule(function() config.hook.after_config() end)
    end

    gtime = (uv.hrtime() - gtime) / 1000000000
    require("r.edit").add_to_debug_info("global setup", gtime, "Time")
end

local M = {}

--- Store user options
---@param opts table User options
M.store_user_opts = function(opts)
    -- Keep track of R.nvim status:
    -- 0: ftplugin/* not sourced yet.
    -- 1: ftplugin/* sourced, but nclientserver not started yet.
    -- 2: nclientserver started, but not ready yet.
    -- 3: nclientserver is ready.
    -- 4: nclientserver started the TCP server
    -- 5: TCP server is ready
    -- 6: R started, but nvimcom was not loaded yet.
    -- 7: nvimcom is loaded.
    if not vim.g.R_Nvim_status then vim.g.R_Nvim_status = 0 end
    user_opts = opts
end

--- Real setup function.
--- Set initial values of some internal variables.
--- Set the default value of config variables that depend on system features.
--- Apply any settings defined in a .Rproj file
M.real_setup = function()
    if not did_real_setup then
        did_real_setup = true
        global_setup()
    end
    if config.hook.on_filetype then
        vim.schedule(function() config.hook.on_filetype() end)
    end
    require("r.rproj").apply_settings(config)

    if config.register_treesitter then
        vim.treesitter.language.register("markdown", { "quarto", "rmd" })
    end
end

--- Return the table with the final configure variables: the default values
--- overridden by user options.
---@return table
M.get_config = function() return config end

M.check_health = function()
    local htime = uv.hrtime()

    -- Check if either Vim-R-plugin or Nvim-R is installed
    if vim.fn.exists("*WaitVimComStart") ~= 0 then
        warn("Please, uninstall Vim-R-plugin before using R.nvim.")
    elseif vim.fn.exists("*RWarningMsg") ~= 0 then
        warn("Please, uninstall Nvim-R before using R.nvim.")
    end

    -- Check R_app asynchronously
    utils.check_executable(config.R_app, function(exists)
        if not exists then
            warn("R_app executable not found: '" .. config.R_app .. "'")
        end
    end)

    -- Check R_cmd asynchronously if it's different from R_app
    if config.R_cmd ~= config.R_app then
        utils.check_executable(config.R_cmd, function(exists)
            if not exists then
                warn("R_cmd executable not found: '" .. config.R_cmd .. "'")
            end
        end)
    end

    if vim.fn.has("nvim-0.9.5") ~= 1 then warn("R.nvim requires Neovim >= 0.9.5") end

    -- Check if treesitter is available
    local function has_parser(parser_name, parsers)
        local path = "parser" .. (config.is_windows and "\\" or "/") .. parser_name .. "."
        for _, v in pairs(parsers) do
            if v:find(path, 1, true) then return true end
        end
        return false
    end
    local has_treesitter, _ = pcall(require, "nvim-treesitter")
    if not has_treesitter then
        warn(
            'R.nvim requires nvim-treesitter. Please install it and the parsers for "r", "markdown", and "rnoweb".'
        )
    else
        -- Check if required treesitter parsers are available
        local parsers = vim.api.nvim_get_runtime_file(
            "parser" .. (config.is_windows and "\\" or "/") .. "*.*",
            true
        )
        if
            not has_parser("r", parsers)
            or not has_parser("markdown", parsers)
            or not has_parser("rnoweb", parsers)
            or not has_parser("yaml", parsers)
        then
            warn(
                'R.nvim requires treesitter parsers for "r", "markdown", "rnoweb", and "yaml". Please, install them.'
            )
        end
    end

    htime = (uv.hrtime() - htime) / 1000000000
    require("r.edit").add_to_debug_info("check health (async)", htime, "Time")
end

return M
