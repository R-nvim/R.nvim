local config = {
    OutDec              = ".",
    Rout_more_colors    = false,
    R_app               = "R",
    R_cmd               = "R",
    R_args              = {},
    after_ob_open       = {},
    after_start         = {},
    applescript         = false,
    arrange_windows     = true,
    assign              = true,
    assign_map          = "<M-->",
    auto_scroll         = true,
    auto_start          = 0,
    bracketed_paste     = false,
    buffer_opts         = "winfixwidth winfixheight nobuflisted",
    clear_console       = true,
    clear_line          = false,
    close_term          = true,
    dbg_jump            = true,
    debug               = true,
    debug_center        = false,
    disable_cmds        = {''},
    editor_w            = 66,
    esc_term            = true,
    external_term       = false, -- might be a string
    fun_data_1          = {'select', 'rename', 'mutate', 'filter'},
    fun_data_2          = {ggplot = {'aes'}, with = '*'},
    help_w              = 46,
    hi_fun_paren        = false,
    insert_mode_cmds    = false,
    latexcmd            = {"default"},
    listmethods         = false,
    min_editor_width    = 80,
    non_r_compl         = true,
    notmuxconf          = false,
    nvim_wd             = 0,
    nvimpager           = "vertical",
    objbr_allnames      = false,
    objbr_auto_start    = false,
    objbr_h             = 10,
    objbr_opendf        = true,
    objbr_openlist      = false,
    objbr_place         = "script,right",
    objbr_w             = 40,
    open_example        = true,
    openhtml            = true,
    openpdf             = 2,
    paragraph_begin     = true,
    parenblock          = true,
    pdfviewer           = "zathura",
    quarto_preview_args = '',
    quarto_render_args  = '',
    rconsole_height     = 15,
    rconsole_width      = 80,
    rmarkdown_args      = "",
    rmd_environment     = ".GlobalEnv",
    rmdchunk            = 2, -- might be a string
    rmhidden            = false,
    rnowebchunk         = true,
    routnotab           = false,
    save_win_pos        = true,
    set_home_env        = true,
    setwidth            = 2,
    silent_term         = false,
    source_args         = "",
    specialplot         = false,
    strict_rst          = true,
    synctex             = true,
    texerr              = true,
    user_maps_only      = false,
    wait                = 60,
    wait_reply          = 2,
}

local user_opts = {}

local set_editing_mode = function ()
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

local validate_user_opts = function()
    -- We don't use vim.validate() because its error message has traceback details not useful for users.
    for k, _ in pairs(user_opts) do
        if config[k] == nil then
            vim.notify("R-Nvim: unrecognized option `" .. k .. "`.", vim.log.levels.WARN)
        else
            if k == "external_term" and not (type(user_opts[k]) == "string" or type(user_opts[k]) == "boolean") then
                vim.notify("R-Nvim: option `external_term` should be either boolean or string.", vim.log.levels.WARN)
            elseif k == "rmdchunk" and not (type(user_opts[k]) == "string" or type(user_opts[k]) == "number") then
                vim.notify("R-Nvim: option `rmdchunk` should be either number or string.", vim.log.levels.WARN)
            elseif not (type(user_opts[k]) == type(config[k])) then
                vim.notify("R-Nvim: option `" .. k .. "` should be " .. type(config[k]) .. ", not " .. type(user_opts[k]) .. ".", vim.log.levels.WARN)
            end
        end
    end
end

M = {}

--- Store user options
---@param opts table User options
M.store_user_opts = function(opts)
    user_opts = opts
end

--- Real setup function.
--- Set initial values of some internal variables.
--- Set the default value of config variables that depend on system features.
M.real_setup = function ()
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
    vim.cmd.runtime("R/common_global.vim")

    -- Override default config values with user options for the second time.
    for k, v in pairs(user_opts) do
        config[k] = v
    end

end

--- Return the table with the final configure variables: the default values
--- overridden by user options.
---@return table
M.get_config = function ()
    return config
end

return M
