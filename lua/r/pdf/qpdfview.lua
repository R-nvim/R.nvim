local cfg = require("r.config").get_config()
local warn = require("r").warn
local M = {}

M.open = function(fullpath)
    vim.fn.system("qpdfview --unique '" .. fullpath .. "' 2>/dev/null >/dev/null &")
    if cfg.synctex then
        local s = string.find(fullpath, " ")
        if s > 0 then
            warn(
                "Qpdfview does not support file names with spaces: SyncTeX backward will not work."
            )
        end
    end
end

M.SyncTeX_forward = function(tpath, ppath, texln, _)
    local texname = string.gsub(tpath, " ", "\\ ")
    local pdfname = string.gsub(ppath, " ", "\\ ")
    vim.fn.system(
        "qpdfview --unique "
            .. pdfname
            .. "#src:"
            .. texname
            .. ":"
            .. texln
            .. ":1 2> /dev/null >/dev/null &"
    )
    require("r.pdf").focus_window(string.gsub(ppath:gsub(".*/", ""), ".pdf$", ""), 0)
end

return M
