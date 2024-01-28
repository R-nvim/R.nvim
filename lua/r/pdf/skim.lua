local M = {}

M.open = function(fullpath)
    vim.fn.system("env NVIMR_PORT=" .. vim.g.rplugin.myport .. " " ..
                 vim.g.rplugin.macvim_skim_app_path .. '/Contents/MacOS/Skim "' ..
                 fullpath .. '" 2> /dev/null >/dev/null &')
end

M.SyncTeX_forward = function(tpath, ppath, texln, _)
    -- This command is based on macvim-skim
    vim.fn.system("NVIMR_PORT=" .. vim.g.rplugin.myport .. " " ..
                vim.g.macvim_skim_app_path .. '/Contents/SharedSupport/displayline -r ' ..
                texln .. ' "' .. ppath .. '" "' .. tpath .. '" 2> /dev/null >/dev/null &')
end

return M
