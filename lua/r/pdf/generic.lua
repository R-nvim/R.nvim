local warn = require("r").warn
local cfg = require("r.config").get_config()

local M = {}

M.open = function(fullpath)
    vim.fn.system(cfg.pdfviewer .. " '" .. fullpath .. "' 2>/dev/null >/dev/null &")
end

M.SyncTeX_forward = function (_, _, _, _)
    warn("R-Nvim has no support for SyncTeX with '" .. cfg.pdfviewer .. "'")
end

return M
