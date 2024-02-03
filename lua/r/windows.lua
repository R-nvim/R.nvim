local config = require("r.config").get_config()
local warn = require("r").warn
local saved_home = nil
local M = {}

M.set_R_home = function()
    -- R and Vim use different values for the $HOME variable.
    if config.set_home_env then
        -- FIXME: try vim.system()
        require("r.edit").add_for_deletion(config.tmpdir .. "/run_cmd.bat")
        saved_home = vim.env.HOME
        local run_cmd_content = {'reg.exe QUERY "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders" /v "Personal"'}
        vim.fn.writefile(run_cmd_content, config.tmpdir .. "/run_cmd.bat")
        local prs = vim.fn.system(config.tmpdir .. "/run_cmd.bat")
        if #prs > 0 then
            prs = vim.fn.substitute(prs, '.*REG_SZ\\s*', '', '')
            prs = vim.fn.substitute(prs, '\n', '', 'g')
            prs = vim.fn.substitute(prs, '\r', '', 'g')
            prs = vim.fn.substitute(prs, '\\s*$', '', 'g')
            vim.env.HOME = prs
        end
    end
end

M.unset_R_home = function()
    if saved_home then
        vim.env.HOME = saved_home
        saved_home = nil
    end
end

M.start_Rgui = function()
    if vim.g.R_Nvim_status == 5 then
        return
    end
    vim.g.R_Nvim_status = 4

    if vim.fn.match(config.R_app, 'Rterm') then
        warn('"R_app" cannot be "Rterm.exe". R will crash if you send any command.')
        vim.wait(200)
    end

    M.set_R_home()
    vim.fn.system("start " .. config.R_app .. ' ' .. table.concat(config.R_args, ' '))
    M.unset_R_home()

    require("r.run").wait_nvimcom_start()
end

-- Called by nvimrserver
M.clean_and_start_Rgui = function()
    require("r.run").clear_R_info()
    M.start_Rgui()
end

M.send_cmd_to_Rgui = function(command, _)
    local cmd
    if config.clear_line then
        cmd = "\001" .. "\013" .. command .. "\n"
    else
        cmd = command .. "\n"
    end
    require("r.job").stdin("Server", "83" .. cmd)
    return 1
end

return M
