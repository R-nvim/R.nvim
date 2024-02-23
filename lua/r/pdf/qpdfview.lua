local config = require("r.config").get_config()
local job = require("r.job")
local warn = require("r").warn
local M = {}

M.open = function(fullpath)
    if config.synctex and fullpath:find(" ") then
        warn("Qpdfview's SyncTeX backward does not support file names with spaces.")
    end

    local opts = {
        on_stdout = require("r.job").on_stdout,
        on_exit = require("r.job").on_exit,
        detach = true,
    }

    local cmd = {
        "qpdfview",
        "--unique",
        fullpath,
    }

    job.start(fullpath, cmd, opts)
end

M.SyncTeX_forward = function(tpath, ppath, texln, _)
    local texname = tpath:gsub(" ", "\\ ")
    local pdfname = ppath:gsub(" ", "\\ ")
    vim.fn.system(
        "qpdfview --unique "
            .. pdfname
            .. "#src:"
            .. texname
            .. ":"
            .. texln
            .. ":1 2> /dev/null >/dev/null &"
    )
    require("r.utils").focus_window(ppath, job.get_pid(ppath))
end

return M
