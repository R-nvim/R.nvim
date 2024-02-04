local config = require("r.config").get_config()
local M = {}

M.open = function(fullpath)
    vim.fn.system(
        config.macvim_skim_app_path
            .. '/Contents/MacOS/Skim "'
            .. fullpath
            .. '" 2> /dev/null >/dev/null &'
    )
end

M.SyncTeX_forward = function(tpath, ppath, texln, _)
    -- This command is based on macvim-skim
    vim.fn.system(
        config.macvim_skim_app_path
            .. "/Contents/SharedSupport/displayline -r "
            .. texln
            .. ' "'
            .. ppath
            .. '" "'
            .. tpath
            .. '" 2> /dev/null >/dev/null &'
    )
end

return M
