local M = {}
local job = require("r.job")
local warn = require("r").warn

local on_okular_stdout = function(_, data, _)
    for _, cmd in ipairs(data) do
        if vim.startswith(cmd, "lua ") then vim.cmd(cmd) end
    end
end

M.open = function(fullpath)
    job.start("OkularSyncTeX", {
        "okular",
        "--unique",
        "--editor-cmd",
        'echo \'lua require("r.rnw").SyncTeX_backward("%f", "%l")\'',
        fullpath,
    }, {
        detach = true,
        on_stdout = on_okular_stdout,
    })
    if job.is_running("Okular") < 1 then warn("Failed to run Okular...") end
end

M.SyncTeX_forward = function(tpath, ppath, texln)
    local texname = vim.fn.substitute(tpath, " ", "\\ ", "g")
    local pdfname = vim.fn.substitute(ppath, " ", "\\ ", "g")
    job.start("OkularSyncTeX", {
        "okular",
        "--unique",
        "--editor-cmd",
        'echo \'lua require("r.rnw").SyncTeX_backward("%f", "%l")\'',
        pdfname .. "#src:" .. texln .. texname,
    }, {
        detach = true,
        on_stdout = on_okular_stdout,
    })
    if job.is_running("OkularSyncTeX") < 1 then
        warn("Failed to run Okular (SyncTeX forward)...")
        return
    end
    require("r.pdf").raise_window(pdfname)
end

return M
