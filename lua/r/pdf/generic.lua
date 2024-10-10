local warn = require("r.log").warn
local config = require("r.config").get_config()
local job = require("r.job")

local M = {}

M.open = function(fullpath)
    if config.pdfviewer == "" then
        vim.ui.open(fullpath)
        return
    end

    local opts = {
        on_exit = require("r.job").on_exit,
        detach = true,
    }
    local cmd = { config.pdfviewer, fullpath }
    job.start(fullpath, cmd, opts)
end

M.SyncTeX_forward = function(_, _, _)
    warn("R.nvim has no support for SyncTeX with '" .. config.pdfviewer .. "'")
end

return M
