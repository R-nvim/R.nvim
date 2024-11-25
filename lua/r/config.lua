local utils = require("r.utils")
local uv = vim.uv
local hooks = require("r.hooks")


---@class RConfigUserOpts
---
---Used to set R's `OutDec` option; see `?options` in R; see |OutDec| or
---`:help OutDec` for more information.
---@field OutDec? string 
---
---Optionally set R.nvim to use RStudio to run R code; see `|RStudio_cmd|` or
---`:help RStudio_cmd` for more information.
---@field RStudio_cmd? string
---
---Optionally override the command used to start R, defaults to `"R"`.
---See |R_app| or `:help R_app` for more information.
---@field R_app? string
---
---Additional command line arguments passed to R on startup. See |R_args| or
---`:help R_args` for more information.
---@field R_args? string[]
---
---This command will be used to run some background scripts; Defaults to the
---same value as |R_app|. See |R_cmd| or `:help R_cmd` for more information.
---@field R_cmd? string
---
---Optionally set the path to the R executable used by R.nvim. The user's
---`PATH` environmental variable will be used by default. See |R_path| or 
---`:help R_path` for more information.
---@field R_path? string
---
---Whether to add additional highlighting to R output; defaultst to `false`.
---See |Rout_more_colors| or `:help Rout_more_colors` for more information.
---@field Rout_more_colors? boolean
---
---Whether to use the R.app graphical application on Mac OS X. Defaults
---to `false`. See |applescript| or `:help applescript` for more information.
---@field applescript? boolean
---
---Whether to remember the window layout when quitting R; defaults to `true`.
---See |arrange_windows| or `:help arrange_windows` for more information.
---@field arrange_windows? boolean
---
---The keymap used to insert `<-`; defaults to `<M-->`, i.e. Alt + M in most
---terminals. See |assignment_keymap| or `:help assignment_keymap` for more
---information.
---@field assignment_keymap? string
---
---The keymap used to insert the pipe operator; defaults to `<localleader>,`.
---See |pipe_keymap| or `:help pipe_keymap` for more information.
---@field pipe_keymap? string
---
---The version of the pipe operator to insert on |pipe_keymap|; defaults to
---`"native"`. See |pipe_version| or `:help pipe_version` for more information.
---@field pipe_version? '"native"' | '"|>"' | '"magrittr"' | '"%>%"'
---
---Whether to force auto-scrolling in the R console; defaults to `true`.
---See |auto_scroll| or `:help auto_scroll` for more information.
---@field auto_scroll? boolean
---
---Whether to start R automatically when you open an R script; defaults to
---`"no". See |auto_start| or `:help auto_start` for more information.
---@field auto_start? '"no"' | '"on startup"' | '"always"'
---
---Whether closing Neovim should also quit R; defaults to `true` in Neovim's
---built-in terminal emulator and `false` otherwise. See |auto_quit| or
---`:help auto_quit` for more information.
---@field auto_quit? boolean
---
---Controls which lines are sent to the R console on `<LocalLeader>pp`;
---defaults to `false`. See |bracketed_paste| or `:help bracketed_paste` for
---more information.
---@field bracketed_paste? boolean
---
---Options to control the behaviour of the R console window; defaults to
---`"winfixwidth winfixheight nobuflisted"`. See `|buffer_opts|` or `:help
---buffer_opts` for more information.
---@field buffer_opts? string
---
---Whether to set a keymap to clear the console; defaults to `true` but should
---be set to `false` if your version of R supports this feature out-of-the-box.
---See |clear_console| or `:help clear_console` for more information.
---@field clear_console? boolean
---
---Set to `true` to add `<C-a><C-k>` to every R command; defaults to `false`.
---See |clear_line| or `:help clear_line` for more information.
---@field clear_line? boolean
---
---Whether to close the terminal window when R quits; defaults to `true`.
---see |close_term| or `:help close_term` for more information.
---@field close_term? boolean
---
---Whether to set a keymap to format all numbers as integers for the current
---buffer; defaults to `false`. See |convert_range_int| or
---`:help convert_range_int` for more informatin.
---@field convert_range_int? boolean
---
---Optionally you can give a directory where lists used for autocompletion
---will be stored. Defaults to `""`. See |compldir| or `:help compldir` for
---more information.
---@field compldir? string
---
---Options for fine-grained control of the object browser. See |compl_data| or
---`:help compl_data` for more information.
---@field compl_data? { max_depth: integer, max_size: integer, max_time: integer }
---
---Whether to use R.nvim's configuration for Tmux if running R in an external
---terminal emulator. Set to `false` if you want to use your own `.tmux.conf`.
---Defaults to `true`. See |config_tmux| or `:help config_tmux` for more
---information.
---@field config_tmux? boolean
---
---Control the program to use when viewing CSV files; defaults to `""`, i.e.
---to open these in a normal Neovim buffer. See |csv_app| or `:help csv_app`
---for more information.
---@field csv_app? string
---
---A table of R.nvim commands to disable. Defaults to `{ "" }`.
---See |disable_cmds| or `:help disable_cmds` for more information.
---@field disable_cmds? table<integer, string>
---
---Set to `"vi"` if R is running in vi editing mode; defaults to `""`.
---See `|editing_mode|` or `:help editing_mode` for more information.
---@field editing_mode? string
---
---Whether to use `<Esc>` to leave terminal mode and enter normal mode;
---defaults to `true`. See |esc_term| or `:help esc_term` for more information.
---@field esc_term? boolean
---
---Whether to run R in an external terminal emulator rather than Noevim's
---built-in terminal emulator; defaults to `false`. See |external_term| or
---`:help external_term` for more information.
---@field external_term? boolean
---
---Whether X tools are avaialble; used for window management. By default the
---availability will be detected from the system, but you can force its use
---by setting this value to `true` or `false`.
---@field has_X_tools? boolean
---
---Whether to highlight R output using Neovim. Defaults to `false` if the
---package {colorout} is loaded, or `true` otherwise. See |hl_term| or 
---`:help hl_term` for more information.
---@field hl_term? boolean
---
---Functions to run on various events. See |hook| or `:help hook` for more
---information.
---@field hook? { on_filetype: RHook, after_config: RHook, after_R_start: RHook, after_ob_open: RHook}
---
---Whether to allow R.nvim commands when in insert mode; defaults to `false`.
---See |insert_mode_cmds| or `:help insert_mode_cmds` for more information.
---@field insert_mode_cmds? boolean
---
---Command and arguments to use when producing PDFs. See |latexcmd| or
---`:help latexcmd` for more information.
---@field latexcmd? table<string, string>
---
---Whether to list arguments for methods on `<localleader>ra`; defaults to
---`false`. See |listmethods| or `:help listmethods` for more information.
---@field listmethods? boolean
---
---Optionally supply the path to the directory where the {nvimcom} is
---installed. See `/doc/remote_access.md` for more information.
---@field local_R_library_dir? string
---
---When sending lines to the console, this is the number of lines at which
---R.nvim will instead create and source a temporary file. Defaults to `20`.
---See |max_paste_lines| or `:help max_paste_lines` for more information.
---@field max_paste_lines? integer
---
---Used to control how R.nvim splits the window when intialising the R console;
---defaults to `80`. See |min_editor_width| or `:help min_editor_width` for
---more information.
---@field min_editor_width? integer
---
---How to set the working directory when starting R; defaults to `"no"` to not
---set the working directory. See |setwd| or `:help setwd` for more
---information.
---@field setwd? '"no"' | '"file"' | '"nvim"'
---
---How to open R man pages/help documentation; defaults to `"split_h"`.
---See |nvimpager| or `:help nvimpager` for more information.
---@field nvimpager? '"split_h"' | '"split_v"' | '"tab"' | '"float"' | '"no"'
---
---Whether to show hidden objects in the object browser; defaults to `false`.
---See |objbr_allnames| or `:help objbr_allnames` for more information.
---@field objbr_allnames? boolean
---
---Whether to start the object browser when R starts; defaults to `false`.
---See |objbr_auto_start| or `:help objbr_auto_start` for more information.
---@field objbr_auto_start? boolean
---
---Default height for the object browser; defaults to `10`. See |objbr_h| or
---`:help objbr_h` for more information.
---@field objbr_h? integer
---
---Whether to expand dataframes in the object browser; defaults to `true`.
---See |objbr_opendf| or `:help objbr_opendf` for more information.
---@field objbr_opendf? boolean
---
---Whether to expand lists in the object browser; defaults to `false`.
---See |objbr_openlist| or `:help objbr_openlist` for more information.
---@field objbr_openlist? boolean
---
---Where to open the object browser; defaults to `"script,right"`.
---See |objbr_place| or `:help objbr_place` for more information.
---@field objbr_place? string
---
---Default width for the object browser; defaults to `40`. See |objbr_w| or
---`:help objbr_w` for more information.
---@field objbr_w? integer
---
---Keymappings to set for the object browser. Table keys give the keymaps
---and values give R functions to call for the object under the cursor.
---Defaults to `{ s = "summary", p = "plot" }`
---@field objbr_mappings? table<string, string>
---
---Optionally a placeholder to use when setting object browser mappings.
---Defaults to `"{object}"`. See |objbr_placeholder| or
---`:help objbr_placeholder` for more information.
---@field objbr_placeholder? string
---
---Whether to open R examples in a Neovim buffer; defaults to `true`.
---See |open_example| or `:help open_example` for more information.
---@field open_example? boolean
---
---How to open HTML files after rendering an R Markdown document; defaults to
---`"open and focus"`. See |open_html| or `:help open_html` for more
---information.
---@field open_html? '"open and focus"' | '"open"' | '"no"'
---
---How to open PDF files after rendering an R Markdown document; defaults to
---`"open and focus"`. See |open_pdf| or `:help open_pdf` for more
---information.
---@field open_pdf? '"open and focus"' | '"open"' | '"no"'
---
---When sending a line, this controls whether preceding lines are also sent if
---they're part of the same paragraph. Defaults to `true`.
---See |paragraph_begin| or `:help paragraph_begin` for more information.
---@field paragraph_begin? boolean
---
---Whether to send the surrounding paragraph when an individual line is
---sent to the R console; defaults to `true`. See |parenblock| or
---`:help parenblock` for more information.
---@field parenblock? boolean
---
---The function to use when splitting a filepath; defaults to `"file.path"`.
---See |path_split_fun| or `:help path_split_fun` for more information.
---@field path_split_fun? string
---
---The program to use to open PDF files; the default behaviour depends on the
---platform. See |pdfviewer| or `:help pdfviewer` for more information.
---@field pdfviewer? string
---
---Additional arguments passed to `quarto::quarto_preview()`; defaults to `""`.
---See |quarto_preview_args| or `:help quarto_preview_args` for more
---information.
---@field quarto_preview_args? string
---
---Additional arguments passed to `quarto::quarto_render()`; defaults to `""`.
---See |quarto_render_args| or `:help quarto_render_args` for more
---information.
---@field quarto_render_args? string
---
---The default height for the R console; defaults to `15`.
---See |rconsole_height| or `:help rconsole_height` for more information.
---@field rconsole_height? integer
---
---The default width for the R console; defaults to `80`.
---See |rconsole_width| or `:help rconsole_width` for more information.
---@field rconsole_width? integer
---
---Whether to register the Markdown parser for Quarto and RMarkdown documents;
---defaults to `true`. See |register_treesitter| or `:help register_treesitter`
---for more information.
---@field register_treesitter? boolean
---
---Options for accessing a remote R session from local Neovim.
---See |remote_compldir| or `:help remote_compldir` for more information.
---@field remote_compldir? string
---
--Whether to automatically remove {knitr} cache files; defaults to `false`.
--This field is undocumented, but users can still apply it if they really
--want to.
--@field private rm_knit_cache? boolean
--
---Additional arguments passed to `rmarkdown::render()`; defaults to `""`.
---See |rmarkdown_args| or `:help rmarkdown_args` for more information.
---@field rmarkdown_args? string
---
---The environment in which to render R Markdown documents; defaults to
---`".GlobalEnv"`. See |rmd_environment| or `:help rmd_environment` for more
---information.
---@field rmd_environment? string
---
---Controls if and how backticks are replaced with code chunk/inline code
---delimiters when writing R Markdown and Quarto files. See |rmdchunk| or
---`:help rmdchunk` for more information.
---@field rmdchunk? string | integer
---
---Whether to remove hidden objects from the workspace on `<LocalLeader>rm`;
---defaults to `false`. See |rmhidden| or `:help rmhidden` for more
---information.
---@field rmhidden? boolean
---S
---Whether to replace `<` with `<<>>=\n@` when writing Rnoweb files; defaults
---to `true`. See |rnowebchunk| or `:help rnowebchunk` for more information.
---@field rnowebchunk? boolean
---
--The directory containing R.nvim's plugin files.
--@field private rnvim_home? string
--
---Controls whether the resulting `.Rout` file is not opened in a new tab when
---running `R CMD BATCH`; defaults to `false`. See |routnotab| or
---`:help routnotab` for more information.
---@field routnotab? boolean
---
---Controls which fields from a `.Rproj` file should influence R.nvim settings.
---Defaults to `{ "pipe_version" }`. See |proj_prioritise| or
---`:help rproj_prioritise` for more information.
---@field rproj_prioritise? table<integer, RprojField>
---
---Whether to save the position of the R console on quit; defaults to `true`.
---See |save_win_pos| or `:help save_win_pos` for more information.
---@field save_win_pos? boolean
---
---Whether to set the `HOME` environmental variable; defaults to `true`.
---See |set_home_env| or `:help set_home_env` for more information.
---@field set_home_env? boolean
---
---Controls how R's `width` option is set by R.nvim; defaults to `2`,
---meaning the value will be set according to the initial width of the R
---console. See |setwidth| or `:help setwidth` for more information.
---@field setwidth? boolean | integer
---
---Whether to display terminal error messages as warnings; defaults to
---`false`. See |silent_term| or `:help silent_term` for more information.
---@field silent_term? boolean
---
--Optionally a path to the program Skim which may be used to open PDF files;
--defaults to '""'.
--@field private skim_app_path? string
---
---Additional arguments passed to `source()` when running R code; defaults to
---`""`. See |source_args| or `:help source_args` for more information.
---@field source_args? string
---
---Whether to use R.nvim's `nvim.plit()` on `<LocalLeader>rg`; defaults to
---`false`. See |specialplot| or `:help specialplot` for more information.
---@field specialplot? boolean
---
---Packages for which to built autocompletions when R starts; defaults to
---`"base,stats,graphics,grDevices,utils,methods"`. See |start_libs| or
---`:help start_libs` for more information.
---@field start_libs? string
---
---Whether to use SyncTex with R.nvim; defaults to `true`. See |synctex| or
---`:help synctex` for more information.
---@field synctex? boolean
---
--The PID of R.nvim's terminal window. This is set internally.
--@field private term_pid? integer
--
--The title of R.nvim's terminal window. This is set internally.
--@field private term_title? string
--
---Controls the display of LaTeX errors and warnings; defaults to `true`
---to output these to the console. See |texerr| or `:help texerr` for more 
---information.
---@field texerr? boolean
---
---Can be used to set a particular directory to use for temporary files;
---defaults to `""` to use the OS default. See |tmpdir| or `:help tmpdir` for
---more information.
---@field tmpdir? string
---
--Internal variable used to store the user login name.
--@field private user_login? string
--
---If `true` then default keymaps will not be created; defaults to `false`.
---See |user_maps_only| or `:help user_maps_only` for more information.
---@field user_maps_only? boolean
---
---Time to wait before loading the {nvimcom} package after starting R; defaults
---to `60` seconds. See |wait| or `:help wait` for more information.
---@field wait? integer

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
        local expected_types = valid_types[key_name] or { type(default_val) }
        if vim.fn.index(expected_types, type(user_opt)) == -1 then
            swarn(
                ("Invalid option type for `%s`. Type should be %s, not %s."):format(
                    key_name,
                    utils.msg_join(expected_types, ", ", ", or ", ""),
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
            config.user_login = vim.fn.system("whoami")
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

    hooks.run(config, "after_config")

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
    hooks.run(config, "on_filetype")
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

    if vim.fn.has("nvim-0.9.5") ~= 1 then swarn("R.nvim requires Neovim >= 0.9.5") end

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
