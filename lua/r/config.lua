local utils = require("r.utils")
local uv = vim.uv
local hooks = require("r.hooks")


---@class RConfigUserOpts
---
---Used to set R's `OutDec` option; see `?options` in R; do `:help OutDec` for
---more information.
---@field OutDec? string
---
---Optionally set R.nvim to use RStudio to run R code; do `:help RStudio_cmd`
---for more information.
---@field RStudio_cmd? string
---
---Optionally override the command used to start R, defaults to `"R"`.
---Do `:help R_app` for more information.
---@field R_app? string
---
---Additional command line arguments passed to R on startup. Do `:help R_args`
---for more information.
---@field R_args? string[]
---
---This command will be used to run some background scripts; Defaults to the
---same value as `R_app`. Do `:help R_cmd` for more information.
---@field R_cmd? string
---
---Optionally set the path to the R executable used by R.nvim. The user's
---`PATH` environmental variable will be used by default. Do `:help R_path`
---for more information.
---@field R_path? string
---
---Whether to add additional highlighting to R output; defaults to `false`.
---Do `:help Rout_more_colors` for more information.
---@field Rout_more_colors? boolean
---
---Whether to remember the window layout when quitting R; defaults to `true`.
---Do `:help arrange_windows` for more information.
---@field arrange_windows? boolean
---
---The version of the pipe operator to insert on pipe keymap; defaults to
---`"native"`. Do `:help pipe_version` for more information.
---@field pipe_version? '"native"' | '"|>"' | '"magrittr"' | '"%>%"'
---
---Whether to force auto-scrolling in the R console; defaults to `true`.
---Do `:help auto_scroll` for more information.
---@field auto_scroll? boolean
---
---Whether to start R automatically when you open an R script; defaults to
---`"no". Do `:help auto_start` for more information.
---@field auto_start? '"no"' | '"on startup"' | '"always"'
---
---Whether closing Neovim should also quit R; defaults to `true` in Neovim's
---built-in terminal emulator and `false` otherwise. Do `:help auto_quit` for
---more information.
---@field auto_quit? boolean
---
---Controls which lines are sent to the R console on `<LocalLeader>pp`;
---defaults to `false`. Do `:help bracketed_paste` for more information.
---@field bracketed_paste? boolean
---
---Options to control the behaviour of the R console window; defaults to
---`"winfixwidth winfixheight nobuflisted"`. See Do `:help buffer_opts` for
---more information.
---@field buffer_opts? string
---
---Whether to set a keymap to clear the console; defaults to `true` but should
---be set to `false` if your version of R supports this feature out-of-the-box.
---Do `:help clear_console` for more information.
---@field clear_console? boolean
---
---Set to `true` to add `<C-a><C-k>` to every R command; defaults to `false`.
---Do `:help clear_line` for more information.
---@field clear_line? boolean
---
---Whether to close the terminal window when R quits; defaults to `true`.
---Do `:help close_term` for more information.
---@field close_term? boolean
---
---Whether to set a keymap to format all numbers as integers for the current
---buffer; defaults to `false`. Do `:help convert_range_int` for more
---information.
---@field convert_range_int? boolean
---
---Optionally you can give a directory where lists used for autocompletion
---will be stored. Defaults to `""`. Do `:help compldir` for more information.
---@field compldir? string
---
---Options for fine-grained control of the object browser. Do `:help compl_data`
---for more information.
---@field compl_data? { max_depth: integer, max_size: integer, max_time: integer }
---
---Whether to use R.nvim's configuration for Tmux if running R in an external
---terminal emulator. Set to `false` if you want to use your own `.tmux.conf`.
---Defaults to `true`. Do `:help config_tmux` for more information.
---@field config_tmux? boolean
---
---Whether to enable support for debugging functions.
---@field debug? boolean
---
---Whether to scroll the buffer to center the cursor on the window when
---debugging jumping.
---@field debug_center? boolean
---
---Whether to jump to R buffer while debugging a function.
---@field debug_jump? boolean
---
---Control the program to use when viewing CSV files; defaults to `""`, i.e.
---to open these in a normal Neovim buffer. Do `:help view_df` for more
---information.
---@field view_df? { open_app: string, how: string, csv_sep: string, n_lines: integer, save_fun: string, open_fun: string }
---
---A table of R.nvim commands to disable. Defaults to `{ "" }`.
---Do `:help disable_cmds` for more information.
---@field disable_cmds? table<integer, string>
---
---Set to `"vi"` if R is running in vi editing mode; defaults to `""`.
---Do `:help editing_mode` for more information.
---@field editing_mode? string
---
---Whether to use `<Esc>` to leave terminal mode and enter normal mode;
---defaults to `true`. Do `:help esc_term` for more information.
---@field esc_term? boolean
---
---Whether to run R in an external terminal emulator rather than Neovim's
---built-in terminal emulator. Do `:help external_term` for more information.
---@field external_term? string
---
---Whether X tools are available; used for window management. By default the
---availability will be detected from the system, but you can force its use
---by setting this value to `true` or `false`.
---@field has_X_tools? boolean
---
---Whether to highlight R output using Neovim. Defaults to `false` if the
---package {colorout} is loaded, or `true` otherwise. Do `:help hl_term` for
---more information.
---@field hl_term? boolean
---
---Functions to run on various events. Do `:help hook` for more information.
---@field hook? { on_filetype: RHook, after_config: RHook, after_R_start: RHook, after_ob_open: RHook}
---
---Whether to allow R.nvim commands when in insert mode; defaults to `false`.
---Do `:help insert_mode_cmds` for more information.
---@field insert_mode_cmds? boolean
---
---Command and arguments to use when producing PDFs. Do `:help latexcmd` for
---more information.
---@field latexcmd? table<string, string>
---
---Directory where the LaTeX log file is expected to be found. Do
---`:help latex_build_dir` for more information.
---@field latex_build_dir? string
---
---Arguments do `Sweave()`. Do `:help sweaveargs` for more information.
---@field sweaveargs? string
---
---Whether to list arguments for methods on `<localleader>ra`; defaults to
---`false`. Do `:help listmethods` for more information.
---@field listmethods? boolean
---
---Optionally supply the path to the directory where the {nvimcom} is
---installed. See `/doc/remote_access.md` for more information.
---@field local_R_library_dir? string
---
---When sending lines to the console, this is the number of lines at which
---R.nvim will instead create and source a temporary file. Defaults to `20`.
---Do `:help max_paste_lines` for more information.
---@field max_paste_lines? integer
---
---Used to control how R.nvim splits the window when initialising the R console;
---defaults to `80`. Do `:help min_editor_width` for more information.
---@field min_editor_width? integer
---
---How to set the working directory when starting R; defaults to `"no"` to not
---set the working directory. Do `:help setwd` for more information.
---@field setwd? '"no"' | '"file"' | '"nvim"'
---
---How to open R man pages/help documentation; defaults to `"split_h"`.
---Do `:help nvimpager` for more information.
---@field nvimpager? '"split_h"' | '"split_v"' | '"tab"' | '"float"' | '"no"'
---
---Whether to show hidden objects in the object browser; defaults to `false`.
---Do `:help objbr_allnames` for more information.
---@field objbr_allnames? boolean
---
---Whether to start the object browser when R starts; defaults to `false`.
---Do `:help objbr_auto_start` for more information.
---@field objbr_auto_start? boolean
---
---Default height for the object browser; defaults to `10`. Do `:help objbr_h`
---for more information.
---@field objbr_h? integer
---
---Whether to expand dataframes in the object browser; defaults to `true`.
---Do `:help objbr_opendf` for more information.
---@field objbr_opendf? boolean
---
---Whether to expand lists in the object browser; defaults to `false`.
---Do `:help objbr_openlist` for more information.
---@field objbr_openlist? boolean
---
---Where to open the object browser; defaults to `"script,right"`.
---Do `:help objbr_place` for more information.
---@field objbr_place? string
---
---Default width for the object browser; defaults to `40`. Do `:help objbr_w`
---for more information.
---@field objbr_w? integer
---
---Keymappings to set for the object browser. Table keys give the keymaps
---and values give R functions to call for the object under the cursor.
---Defaults to `{ s = "summary", p = "plot" }`
---@field objbr_mappings? table<string, string>
---
---Optionally a placeholder to use when setting object browser mappings.
---Defaults to `"{object}"`. Do `:help objbr_placeholder` for more information.
---@field objbr_placeholder? string
---
---Whether to open R examples in a Neovim buffer; defaults to `true`.
---Do `:help open_example` for more information.
---@field open_example? boolean
---
---How to open HTML files after rendering an R Markdown document; defaults to
---`"open and focus"`. Do `:help open_html` for more information.
---@field open_html? '"open and focus"' | '"open"' | '"no"'
---
---How to open PDF files after rendering an R Markdown document; defaults to
---`"open and focus"`. Do `:help open_pdf` for more information.
---@field open_pdf? '"open and focus"' | '"open"' | '"no"'
---
---When sending a line, this controls whether preceding lines are also sent if
---they're part of the same paragraph. Defaults to `true`.
---Do `:help paragraph_begin` for more information.
---@field paragraph_begin? boolean
---
---Whether to send the surrounding paragraph when an individual line is
---sent to the R console; defaults to `true`. Do `:help parenblock` for more
---information.
---@field parenblock? boolean
---
---The function to use when splitting a filepath; defaults to `"file.path"`.
---Do `:help path_split_fun` for more information.
---@field path_split_fun? string
---
---The program to use to open PDF files; the default behaviour depends on the
---platform. Do `:help pdfviewer` for more information.
---@field pdfviewer? string
---
---Additional arguments passed to `quarto::quarto_preview()`; defaults to `""`.
---Do `:help quarto_preview_args` for more information.
---@field quarto_preview_args? string
---
---Additional arguments passed to `quarto::quarto_render()`; defaults to `""`.
---Do `:help quarto_render_args` for more information.
---@field quarto_render_args? string
---
---The default height for the R console; defaults to `15`.
---Do `:help rconsole_height` for more information.
---@field rconsole_height? integer
---
---The default width for the R console; defaults to `80`.
---Do `:help rconsole_width` for more information.
---@field rconsole_width? integer
---
---Whether to register the Markdown parser for Quarto and RMarkdown documents;
---defaults to `true`. Do `:help register_treesitter` for more information.
---@field register_treesitter? boolean
---
---Options for accessing a remote R session from local Neovim.
---Do `:help remote_compldir` for more information.
---@field remote_compldir? string
---
---Whether to automatically remove {knitr} cache files; defaults to `false`.
---This field is undocumented, but users can still apply it if they really
---want to.
---@field rm_knit_cache? boolean
---
---Additional arguments passed to `rmarkdown::render()`; defaults to `""`.
---Do `:help rmarkdown_args` for more information.
---@field rmarkdown_args? string
---
---The environment in which to render R Markdown documents; defaults to
---`".GlobalEnv"`. Do `:help rmd_environment` for more information.
---@field rmd_environment? string
---
---Whether to remove hidden objects from the workspace on `<LocalLeader>rm`;
---defaults to `false`. Do `:help rmhidden` for more information.
---@field rmhidden? boolean
---
---Controls whether the resulting `.Rout` file is not opened in a new tab when
---running `R CMD BATCH`; defaults to `false`. Do `:help routnotab` for more
---information.
---@field routnotab? boolean
---
---Controls which fields from a `.Rproj` file should influence R.nvim settings.
---Defaults to `{ "pipe_version" }`. Do `:help rproj_prioritise` for more
---information.
---@field rproj_prioritise? table<integer, RprojField>
---
---Whether to save the position of the R console on quit; defaults to `true`.
---Do `:help save_win_pos` for more information.
---@field save_win_pos? boolean
---
---Whether to set the `HOME` environmental variable; defaults to `true`.
---Do `:help set_home_env` for more information.
---@field set_home_env? boolean
---
---Controls how R's `width` option is set by R.nvim; defaults to `2`,
---meaning the value will be set according to the initial width of the R
---console. Do `:help setwidth` for more information.
---@field setwidth? integer
---
---Whether to display terminal error messages as warnings; defaults to
---`false`. Do `:help silent_term` for more information.
---@field silent_term? boolean
---
---Path to the program Skim which may be used to open PDF files;
---defaults to '""'.
---@field skim_app_path? string
---
---Additional arguments passed to `source()` when running R code; defaults to
---`""`. Do `:help source_args` for more information.
---@field source_args? string
---
---Whether to use R.nvim's `nvim.plit()` on `<LocalLeader>rg`; defaults to
---`false`. Do `:help specialplot` for more information.
---@field specialplot? boolean
---
---Packages for which to built autocompletions when R starts; defaults to
---`"base,stats,graphics,grDevices,utils,methods"`. Do `:help start_libs` for
---more information.
---@field start_libs? string
---
---Whether to use SyncTex with R.nvim; defaults to `true`. Do `:help synctex`
---for more information.
---@field synctex? boolean
---
---Controls the display of LaTeX errors and warnings; defaults to `true`
---to output these to the console. Do `:help texerr` for more information.
---@field texerr? boolean
---
---Can be used to set a particular directory to use for temporary files;
---defaults to `""` to use the OS default. Do `:help tmpdir` for more
---information.
---@field tmpdir? string
---
--Internal variable used to store the user login name.
--@field private user_login? string
--
---If `true` then default keymaps will not be created; defaults to `false`.
---Do `:help user_maps_only` for more information.
---@field user_maps_only? boolean
---
---Time to wait before loading the {nvimcom} package after starting R; defaults
---to `60` seconds. Do `:help wait` for more information.
---@field wait? integer
---
---Set `params` based on the YAML header for R Markdown and
---Quarto documents. Defaults to `"yes"`.
---@field set_params? '"no"' | '"no_override"' | '"yes"'

---@alias RprojField '"pipe_version"'

---@alias RHook fun(): nil

---@class RConfig: RConfigUserOpts
---@field uname? string
---@field is_windows? boolean
---@field is_darwin? boolean
---@field rnvim_home? string
---@field uservimfiles? string
---@field user_login? string
---@field localtmpdir? string
---@field source_read? string
---@field source_write? string
---@field curview? string
---@field term_title? string -- Pid of window application.
---@field term_pid? integer -- Part of the window title.
---@field R_Tmux_pane? string
---@field R_prompt_str? string
---@field R_continue_str? string

-- stylua: ignore start
---@type RConfig
local config = {
    OutDec              = ".",
    RStudio_cmd         = "",
    R_app               = "R",
    R_args              = {},
    R_cmd               = "R",
    R_path              = "",
    Rout_more_colors    = false,
    arrange_windows     = true,
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
    debug               = true,
    debug_center        = false,
    debug_jump          = true,
    disable_cmds        = { "" },
    editing_mode        = "",
    esc_term            = true,
    external_term       = "",
    has_X_tools         = false,
    hl_term             = true,
    hook                = {
                              on_filetype = function() end,
                              after_config = function() end,
                              after_R_start = function() end,
                              after_ob_open = function() end,
                          },
    insert_mode_cmds    = false,
    latexcmd            = { "default" },
    latex_build_dir     = "",
    sweaveargs          = "",
    listmethods         = false,
    local_R_library_dir = "",
    max_paste_lines     = 20,
    min_editor_width    = 80,
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
    rmhidden            = false,
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
    texerr              = true,
    tmpdir              = "",
    user_login          = "",
    user_maps_only      = false,
    view_df = {
        open_app = "",  -- How to open the CSV in Neovim or an external application.
        how = "tabnew", -- How to display the data within Neovim if not using an external application.
        csv_sep = "",   -- Field separator to be used when saving the CSV.
        n_lines = -1,   -- Number of lines to save in the CSV (0 for all lines).
        save_fun = "",  -- Save the data.frame in a CSV file
        open_fun = "",  -- Use an R function to open the data.frame directly (no conversion to CSV needed)
    },
    wait                = 60,
    set_params          = "yes",
}

-- stylua: ignore end

local user_opts = {}
local did_real_setup = false
local unix = require("r.platform.unix")
local windows = require("r.platform.windows")

local smsgs = {}
local swarn = function(msg)
    table.insert(smsgs, msg)
    require("r.log").warn(msg)
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
        if config.skim_app_path == "" then
            config.skim_app_path = "/Applications/Skim.app"
        end
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
        "set_params",
    }) do
        if user_opts[v] then user_opts[v] = string.lower(user_opts[v]) end
    end

    -- stylua: ignore start

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
        set_params       = { "no", "no_override", "yes"},
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
                ---@type any
                default_val = nil
                break
            end
        end

        -----------------------------------------------------------------------
        -- 1. Check the option exists
        -----------------------------------------------------------------------
        if default_val == nil then
            swarn("Invalid option `" .. key_name .. "`.")
            return
        end

        -----------------------------------------------------------------------
        -- 2. Check the option has one of the expected types
        -----------------------------------------------------------------------
        if type(default_val) ~= type(user_opt) then
            swarn(
                ("Invalid option type for `%s`. Type should be %s, not %s."):format(
                    key_name,
                    type(default_val),
                    type(user_opt)
                )
            )
            return
        end

        -----------------------------------------------------------------------
        -- 3. Check the option has one of the expected values
        -----------------------------------------------------------------------
        local expected_values = valid_values[key_name]
        if expected_values and vim.fn.index(expected_values, user_opt) == -1 then
            swarn(
                ('Invalid option value for `%s`. Value should be %s, not "%s"'):format(
                    key_name,
                    utils.msg_join(expected_values, ", ", ", or "),
                    user_opt
                )
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
            local obj = vim.system({ "whoami" }, { text = true }):wait()
            if obj and obj.stdout ~= "" then
                config.user_login = obj.stdout:gsub("\n", "")
            else
                config.user_login = "WhoAmI"
                swarn("The command whoami failled.")
            end
        else
            config.user_login = "NoLoginName"
            swarn("Could not determine user name.")
        end
    end

    config.user_login = config.user_login:gsub(".*\\", "")
    config.user_login = config.user_login:gsub("[^%w]", "")
    if config.user_login == "" then
        config.user_login = "NoLoginName"
        swarn("Could not determine user name.")
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
    local first_line = "Last change in this file: 2024-10-29"
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
    if config.RStudio_cmd ~= "" or (config.is_windows and config.external_term ~= "") then
        -- Sending multiple lines at once to either Rgui on Windows or RStudio does not work.
        config.max_paste_lines = 1
        config.bracketed_paste = false
        config.parenblock = false
    end

    if config.external_term == "" then
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
    if #objbrplace > 2 then swarn("Too many options for R_objbr_place.") end
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
            swarn(
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
        if config.external_term == "" then
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

local global_setup = function()
    local gtime = uv.hrtime()

    if vim.g.R_Nvim_status == 0 then vim.g.R_Nvim_status = 1 end

    set_pdf_viewer()
    apply_user_opts()

    -- Config values that depend on either system features or other config
    -- values.
    set_editing_mode()

    if config.external_term == "" then config.auto_quit = true end

    -- Load functions that were not converted to Lua yet
    -- Configure more values that depend on either system features or other
    -- config values.
    -- Fix some invalid values
    -- Calls to system() and executable() must run
    -- asynchronously to avoid slow startup on macOS.
    -- See https://github.com/jalvesaq/Nvim-R/issues/625
    do_common_global()
    if config.is_windows then
        windows.configure(config)
    else
        unix.configure(config)
    end

    -- Override default config values with user options for the second time.
    for k, v in pairs(user_opts) do
        config[k] = v
    end

    require("r.commands").create_user_commands()
    vim.fn.timer_start(1, require("r.config").check_health)
    vim.schedule(function() require("r.server").check_nvimcom_version() end)

    hooks.run(config, "after_config", true)

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

    -- The third argument must be `false`, otherwise :RMapsDesc will not display
    -- custom key mappings.
    hooks.run(config, "on_filetype", false)

    require("r.rproj").apply_settings(config)

    if config.register_treesitter then
        vim.treesitter.language.register("markdown", { "quarto", "rmd" })
    end
end

--- Return the table with the final configure variables: the default values
--- overridden by user options.
---@return RConfig
M.get_config = function() return config end

M.check_health = function()
    local htime = uv.hrtime()

    -- Check if either Vim-R-plugin or Nvim-R is installed
    if vim.fn.exists("*WaitVimComStart") ~= 0 then
        swarn("Please, uninstall Vim-R-plugin before using R.nvim.")
    elseif vim.fn.exists("*RWarningMsg") ~= 0 then
        swarn("Please, uninstall Nvim-R before using R.nvim.")
    end

    -- Check R_app asynchronously
    utils.check_executable(config.R_app, function(exists)
        if not exists then
            swarn("R_app executable not found: '" .. config.R_app .. "'")
        end
    end)

    -- Check R_cmd asynchronously if it's different from R_app
    if config.R_cmd ~= config.R_app then
        utils.check_executable(config.R_cmd, function(exists)
            if not exists then
                swarn("R_cmd executable not found: '" .. config.R_cmd .. "'")
            end
        end)
    end

    if vim.fn.has("nvim-0.10.4") ~= 1 then swarn("R.nvim requires Neovim >= 0.10.4") end

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
        swarn(
            'R.nvim requires nvim-treesitter. Please install it and the parsers for "r", "markdown", "rnoweb", and "yaml".'
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
            swarn(
                'R.nvim requires treesitter parsers for "r", "markdown", "rnoweb", and "yaml". Please, install them.'
            )
        end
    end

    if #smsgs > 0 then
        local msg = "\n  " .. table.concat(smsgs, "\n  ")
        require("r.edit").add_to_debug_info("Startup warnings", msg)
    end

    htime = (uv.hrtime() - htime) / 1000000000
    require("r.edit").add_to_debug_info("check health (async)", htime, "Time")
end

return M
