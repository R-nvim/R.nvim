local cfg = require("r.config").get_config()

local M = {}

M.open = function(fullpath)
    vim.fn.system("env NVIMR_PORT=" .. vim.g.rplugin.myport ..
                " qpdfview --unique '" .. fullpath .. "' 2>/dev/null >/dev/null &")
    if cfg.synctex then
        local s = string.find(fullpath, " ")
        if s > 0 then
            vim.notify("Qpdfview does support file names with spaces: SyncTeX backward will not work.", vim.log.levels.WARN)
        end
    end
end

M.SyncTeX_forward = function (tpath, ppath, texln, _)
    local texname = string.gsub(tpath, ' ', '\\ ')
    local pdfname = string.gsub(ppath, ' ', '\\ ')
    vim.fn.system("NVIMR_PORT=" .. vim.g.rplugin.myport .. " qpdfview --unique " ..
    pdfname .. "#src:" .. texname .. ":" .. texln .. ":1 2> /dev/null >/dev/null &")
    vim.fn.RRaiseWindow(string.gsub(string.gsub(ppath, ".*/", ""), ".pdf$", ""))
end

return M
