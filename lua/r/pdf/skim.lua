local config = require("r.config").get_config()
local warn = require("r.log").warn
local M = {}

local on_exit = function(obj)
    if obj.code ~= 0 then
        warn(
            "Skim exit code: "
                .. tostring(obj.code)
                .. "\nstdout: "
                .. obj.stdout
                .. "\nstderr: "
                .. obj.stderr
        )
    end
end

---Open the PDF in Skim
---@param fullpath string
M.open = function(fullpath)
    vim.system(
        { config.skim_app_path .. "/Contents/MacOS/Skim", fullpath },
        { text = true },
        on_exit
    )
end

---Send the SyncTeX forward command to Skim
---@param tpath string
---@param ppath string
---@param texln number
M.SyncTeX_forward = function(tpath, ppath, texln)
    -- This command is based on macvim-skim
    vim.system({
        config.skim_app_path .. "/Contents/SharedSupport/displayline",
        "-r",
        tostring(texln),
        ppath,
        tpath,
    }, { text = true }, on_exit)
end

return M
