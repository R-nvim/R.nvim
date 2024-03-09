local warn = require("r").warn
local uv = vim.loop

-- stylua: ignore start

local config = {
    OutDec              = ".",
    RStudio_cmd         = "",
    R_app               = "R",
    R_args              = {},
    R_cmd               = "R",
    R_path              = "",
    Rout_more_colors    = false,
    active_window_warn  = true,
    applescript         = false,
    arrange_windows     = true,
    assign              = true,
    assign_map          = "<M-->",
    auto_scroll         = true,
    auto_start          = "no",
    bracketed_paste     = false,
    buffer_opts         = "winfixwidth winfixheight nobuflisted",
    clear_console       = true,
    clear_line          = false,
    close_term          = true,
    compldir            = "",
    config_tmux         = true,
    csv_app             = "",
    disable_cmds        = { "" },
    editing_mode        = "",
    esc_term            = true,
    external_term       = false, -- might be a string
    has_X_tools         = false,
    help_w              = 46,
    hi_fun_paren        = false,
    hl_term             = true,
    hook                = {
                              after_config = nil,
                              after_R_start = nil,
                              after_ob_open = nil
                          },
    insert_mode_cmds    = false,
    latexcmd            = { "default" },
    listmethods         = false,
    local_R_library_dir = "",
    max_paste_lines     = 20,
    min_editor_width    = 80,
    non_r_compl         = true,
    setwd               = "no",
    nvimpager           = "split",
    objbr_allnames      = false,
    objbr_auto_start    = false,
    objbr_h             = 10,
    objbr_opendf        = true,
    objbr_openlist      = false,
    objbr_place         = "script,right",
    objbr_w             = 40,
    open_example        = true,
    open_html           = "open and focus",
    open_pdf            = "open and focus",
    paragraph_begin     = true,
    parenblock          = true,
    pdfviewer           = "undefined",
    quarto_preview_args = "",
    quarto_render_args  = "",
    rconsole_height     = 15,
    rconsole_width      = 80,
    remote_compldir     = "",
    rm_knit_cache       = false,
    rmarkdown_args      = "",
    rmd_environment     = ".GlobalEnv",
    rmdchunk            = 2, -- might be a string
    rmhidden            = false,
    rnowebchunk         = true,
    rnvim_home          = "",
    routnotab           = false,
    save_win_pos        = true,
    set_home_env        = true,
    setwidth            = 2,
    silent_term         = false,
    skim_app_path       = "",
    source_args         = "",
    specialplot         = false,
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

local config_keys

local user_opts = {}
local did_global_setup = false

local show_config = function(tbl)
    local opt = tbl.args
    if opt and opt:len() > 0 then
        opt = opt:gsub(" .*", "")
        print(vim.inspect(config[opt]))
    else
        print(vim.inspect(config))
    end
end

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

local compare_types = function(k)
    if k == "external_term" then
        if not (type(user_opts[k]) == "string" or type(user_opts[k]) == "boolean") then
            warn("Option `external_term` should be either boolean or string.")
        end
    elseif k == "rmdchunk" then
        if not (type(user_opts[k]) == "string" or type(user_opts[k]) == "number") then
            warn("Option `rmdchunk` should be either number or string.")
        end
    elseif k == "csv_app" then
        if not (type(config[k]) == "string" or type(config[k]) == "function") then
            warn("Option `csv_app` should be either string or function.")
        end
    elseif type(config[k]) ~= "nil" and (type(user_opts[k]) ~= type(config[k])) then
        warn(
            "Option `"
                .. k
                .. "` should be "
                .. type(config[k])
                .. ", not "
                .. type(user_opts[k])
                .. "."
        )
    end
end

local validate_user_opts = function()
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

    -- We don't use vim.validate() because its error message has traceback details not helpful for users.
    for k, _ in pairs(user_opts) do
        local has_key = false
        for _, v in pairs(config_keys) do
            if v == k then
                has_key = true
                break
            end
        end
        if not has_key then
            warn("Unrecognized option `" .. k .. "`.")
        else
            compare_types(k)
        end
    end

    local validate_string = function(opt, valid_values)
        if user_opts[opt] then
            for _, v in pairs(valid_values) do
                if user_opts[opt] == v then return end
            end
            local vv = ' "' .. table.concat(valid_values, '", "') .. '".'
            warn("Valid values for `" .. opt .. "` are:" .. vv)
        end
    end

    validate_string("auto_start", { "no", "on startup", "always" })
    validate_string("editing_mode", { "vi", "emacs" })
    validate_string("nvimpager", { "no", "tab", "split", "float" })
    validate_string("open_html", { "no", "open", "open and focus" })
    validate_string("open_pdf", { "no", "open", "open and focus" })
    validate_string("setwd", { "no", "file", "nvim" })
end

local do_common_global = function()
    local utils = require("r.utils")

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
    local first_line = "Last change in this file: 2024-03-09"
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
        config.nvimpager = "split"
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

local resolve_fullpaths = function(tbl)
    for i, v in ipairs(tbl) do
        tbl[i] = uv.fs_realpath(v)
    end
end

local windows_config = function()
    local utils = require("r.utils")
    local wtime = uv.hrtime()
    local isi386 = false

    if config.R_path ~= "" then
        local rpath = vim.split(config.R_path, ";")
        resolve_fullpaths(rpath)
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

        local run_cmd = { "reg.exe", "QUERY", "HKCU\\SOFTWARE\\R-core\\R", "/s" }
        local rip = get_rip(run_cmd)
        if #rip == 0 then
            -- Normally, 32 bit applications access only 32 bit registry and...
            -- We have to try again if the user has installed R only in the other architecture.
            if vim.fn.has("win64") then
                table.insert(run_cmd, "/reg:64")
            else
                table.insert(run_cmd, "/reg:32")
            end
            rip = get_rip(run_cmd)
        end

        if #rip == 0 then
            warn(
                "Could not find R path in Windows Registry. "
                    .. "If you have already installed R, please, set the value of 'R_path'."
            )
            wtime = (uv.hrtime() - wtime) / 1000000000
            require("r.edit").add_to_debug_info("windows setup", wtime, "Time")
            return
        end

        local rinstallpath = nil
        rinstallpath = rip[1]
        rinstallpath = rinstallpath:gsub(".*InstallPath.*REG_SZ%s*", "")
        rinstallpath = rinstallpath:gsub("\n", "")
        rinstallpath = rinstallpath:gsub("%s*$", "")
        local hasR32 = vim.fn.isdirectory(rinstallpath .. "\\bin\\i386")
        local hasR64 = vim.fn.isdirectory(rinstallpath .. "\\bin\\x64")
        if hasR32 == 1 and not hasR64 then isi386 = true end
        if hasR64 == 1 and not hasR32 then isi386 = false end
        if hasR32 == 1 and isi386 then
            vim.env.PATH = rinstallpath .. "\\bin\\i386;" .. vim.env.PATH
        elseif hasR64 and isi386 == 0 then
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
        resolve_fullpaths(rpath)

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

    if vim.fn.executable(config.R_app) ~= 1 then
        warn(
            '"'
                .. config.R_app
                .. '" not found. Fix the value of either R_path or R_app in your config.'
        )
    end

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
    did_global_setup = true
    validate_user_opts()

    -- Override default config values with user options for the first time.
    -- Some config options depend on others to have their default values set.
    for k, v in pairs(user_opts) do
        config[k] = v
    end

    -- Config values that depend on either system features or other config
    -- values.
    set_editing_mode()

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
    set_pdf_viewer()

    -- Override default config values with user options for the second time.
    for k, v in pairs(user_opts) do
        config[k] = v
    end

    vim.fn.timer_start(1, require("r.config").check_health)

    -- Commands:
    -- See: :help lua-guide-commands-create
    vim.api.nvim_create_user_command(
        "RStop",
        function(_) require("r.run").signal_to_R("SIGINT") end,
        {}
    )
    vim.api.nvim_create_user_command(
        "RKill",
        function(_) require("r.run").signal_to_R("SIGKILL") end,
        {}
    )
    vim.api.nvim_create_user_command("RBuildTags", require("r.edit").build_tags, {})
    vim.api.nvim_create_user_command("RDebugInfo", require("r.edit").show_debug_info, {})
    vim.api.nvim_create_user_command("RMapsDesc", require("r.maps").show_map_desc, {})

    vim.api.nvim_create_user_command(
        "RSend",
        function(tbl) require("r.send").cmd(tbl.args) end,
        { nargs = 1 }
    )

    vim.api.nvim_create_user_command(
        "RFormat",
        require("r.run").formart_code,
        { range = "%" }
    )

    vim.api.nvim_create_user_command(
        "RInsert",
        function(tbl) require("r.run").insert(tbl.args, "here") end,
        { nargs = 1 }
    )

    vim.api.nvim_create_user_command(
        "RSourceDir",
        function(tbl) require("r.run").source_dir(tbl.args) end,
        { nargs = 1, complete = "dir" }
    )

    vim.api.nvim_create_user_command(
        "RHelp",
        function(tbl) require("r.doc").ask_R_help(tbl.args) end,
        {
            nargs = "?",
            complete = require("r.server").list_objs,
        }
    )

    vim.api.nvim_create_user_command("RConfigShow", show_config, {
        nargs = "?",
        complete = function() return config_keys end,
    })

    vim.fn.timer_start(1, require("r.server").check_nvimcom_version)
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
M.real_setup = function()
    local gtime = uv.hrtime()

    if vim.g.R_Nvim_status == 0 then vim.g.R_Nvim_status = 1 end

    config_keys = {}
    for k, _ in pairs(config) do
        table.insert(config_keys, tostring(k))
    end

    if not did_global_setup then global_setup() end

    if
        config.auto_start:find("always")
        or (config.auto_start:find("startup") and vim.v.vim_did_enter == 0)
    then
        require("r.run").auto_start_R()
    end

    gtime = (uv.hrtime() - gtime) / 1000000000
    require("r.edit").add_to_debug_info("global setup", gtime, "Time")
    if config.hook.after_config then config.hook.after_config() end
end

--- Return the table with the final configure variables: the default values
--- overridden by user options.
---@return table
M.get_config = function() return config end

M.check_health = function()
    -- Check if either Vim-R-plugin or Nvim-R is installed
    if vim.fn.exists("*WaitVimComStart") ~= 0 then
        warn("Please, uninstall Vim-R-plugin before using R.nvim.")
    elseif vim.fn.exists("*RWarningMsg") ~= 0 then
        warn("Please, uninstall Nvim-R before using R.nvim.")
    end

    if vim.fn.executable(config.R_app) == 0 then
        warn("R_app executable not found: '" .. config.R_app .. "'")
    end

    if not config.R_cmd == config.R_app and vim.fn.executable(config.R_cmd) == 0 then
        warn("R_cmd executable not found: '" .. config.R_cmd .. "'")
    end

    if vim.fn.has("nvim-0.9.5") ~= 1 then warn("R.nvim requires Neovim >= 0.9.5") end
end

return M
