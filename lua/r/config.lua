local config = {
    OutDec              = ".",
    Rout_more_colors    = 0,
    R_app               = "R",
    R_cmd               = "R",
    R_args              = {},
    after_ob_open       = {},
    after_start         = {},
    applescript         = 0,
    arrange_windows     = 1,
    assign              = 1,
    assign_map          = "<M-->",
    auto_scroll         = 1,
    auto_start          = 0,
    bracketed_paste     = 0,
    buffer_opts         = "winfixwidth winfixheight nobuflisted",
    clear_console       = 1,
    clear_line          = 0,
    close_term          = 1,
    dbg_jump            = 1,
    debug               = 1,
    debug_center        = 0,
    disable_cmds        = {''},
    editor_w            = 66,
    esc_term            = 1,
    external_term       = 0,
    fun_data_1          = {'select', 'rename', 'mutate', 'filter'},
    fun_data_2          = {ggplot = {'aes'}, with = '*'},
    help_w              = 46,
    hi_fun_paren        = 0,
    insert_mode_cmds    = 0,
    latexcmd            = {"default"},
    listmethods         = 0,
    min_editor_width    = 80,
    never_unmake_menu   = 0,
    non_r_compl         = 1,
    notmuxconf          = 0,
    nvim_wd             = 0,
    nvimpager           = "vertical",
    objbr_allnames      = 0,
    objbr_auto_start    = 0,
    objbr_h             = 10,
    objbr_opendf        = 1,
    objbr_openlist      = 0,
    objbr_place         = "script,right",
    objbr_w             = 40,
    open_example        = 1,
    openhtml            = 1,
    openpdf             = 2,
    paragraph_begin     = 1,
    parenblock          = 1,
    pdfviewer           = "zathura",
    quarto_preview_args = '',
    quarto_render_args  = '',
    rconsole_height     = 15,
    rconsole_width      = 80,
    rmarkdown_args      = "",
    rmd_environment     = ".GlobalEnv",
    rmdchunk            = 2,
    rmhidden            = 0,
    rnowebchunk         = 1,
    routnotab           = 0,
    save_win_pos        = 1,
    set_home_env        = 1,
    setwidth            = 2,
    silent_term         = 0,
    source_args         = "",
    specialplot         = 0,
    strict_rst          = 1,
    synctex             = 1,
    texerr              = 1,
    tmux_title          = 'NvimR',
    user_maps_only      = 0,
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
        for _, v in pairs(inputrc) do
            line = string.gsub(v, "^%s*#.*", "")
            if string.find(line, "set.*editing-mode") then
                em = string.gsub(line, "^%s*%sediting-mode%s*", "")
                em = string.gsub(em, "%s*", "")
            end
        end
    end
    config.editing_mode = em
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
