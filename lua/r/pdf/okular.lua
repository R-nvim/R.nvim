local M = {}
local job = require("r.job")

---Open PDF in Okular
---@param fullpath string
M.open = function(fullpath)
    local opts = {
        on_stdout = require("r.job").on_stdout,
        on_exit = require("r.job").on_exit,
        detach = true,
    }

    local cmd = {
        "okular",
        "--unique",
        "--editor-cmd",
        'echo \'lua require("r.rnw").SyncTeX_backward("%f", %l)\'',
        fullpath,
    }

    job.start(fullpath, cmd, opts)
end

---Send the SyncTeX forward command to Okular
---@param tpath string
---@param ppath string
---@param texln number
M.SyncTeX_forward = function(tpath, ppath, texln)
    local texname = tpath:gsub(" ", "\\ ")
    local pdfname = ppath:gsub(" ", "\\ ")
    job.start("OkularSyncTeX", {
        "okular",
        "--editor-cmd",
        'echo \'lua require("r.rnw").SyncTeX_backward("%f", %l)\'',
        pdfname .. "#src:" .. texln .. texname,
    }, {
        detach = true,
        on_stdout = require("r.job").on_stdout,
        on_exit = require("r.job").on_exit,
    })
    require("r.utils").focus_window(ppath, job.get_pid(ppath))
end

return M
