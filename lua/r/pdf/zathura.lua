local warn = require("r.log").warn
local utils = require("r.utils")
local job = require("r.job")

local M = {}

--- Use Zathura to open PDF document
---@param fullpath string
M.open = function(fullpath)
    local zopts = {
        on_stdout = require("r.job").on_stdout,
        on_exit = require("r.job").on_exit,
        detach = true,
    }

    local zcmd = {
        "zathura",
        "--synctex-editor-command",
        'echo \'lua require("r.rnw").SyncTeX_backward("%{input}", %{line})\'',
        fullpath,
    }
    job.start(fullpath, zcmd, zopts)
end

--- Start Zathura with SyncTeX forward arguments.
---@param tpath string LaTeX document path.
---@param ppath string PDF document path.
---@param texln number Line number in the LaTeX document.
M.SyncTeX_forward = function(tpath, ppath, texln)
    local texname = tpath:gsub(" ", "\\ ")
    local pdfname = ppath:gsub(" ", "\\ ")
    local shortp = ppath:gsub(".*/", "")

    local zfcmd = {
        "zathura",
        "--synctex-forward=" .. texln .. ":1:" .. texname,
        "--synctex-pid=" .. job.get_pid(ppath),
        pdfname,
    }
    local obj = vim.system(zfcmd, { text = true }):wait()
    if obj.code ~= 0 then
        warn(obj.stderr)
        return
    end

    utils.focus_window(shortp, job.get_pid(ppath))
end

return M
