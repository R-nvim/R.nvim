local warn = require("r").warn
local pdf = require("r.pdf")
local job = require("r.job")

---@param fullpath string
local start_zathura = function(fullpath)
    if job.is_running(fullpath) then
        local fname = fullpath:gsub(".*/", "")
        pdf.raise_window(fname, job.get_pid(fullpath))
        return
    end

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

local M = {}

--- Use Zathura to open PDF document
---@param fullpath string
M.open = function(fullpath)
    local fname = fullpath:gsub(".*/", "")
    if job.is_running(fullpath) then
        pdf.raise_window(fname, job.get_pid(fullpath))
        return
    end
    start_zathura(fullpath)
end

--- Start Zathura with SyncTeX forward arguments.
---@param tpath string LaTeX document path.
---@param ppath string PDF document path.
---@param texln number Line number in the LaTeX document.
M.SyncTeX_forward = function(tpath, ppath, texln)
    local texname = vim.fn.substitute(tpath, " ", "\\ ", "g")
    local pdfname = vim.fn.substitute(ppath, " ", "\\ ", "g")
    local shortp = vim.fn.substitute(ppath, ".*/", "", "g")

    -- FIXME: this should not be necessary:
    ppath = ppath:gsub("//", "/")

    if not job.is_running(ppath) then
        start_zathura(ppath)
        return
    end

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

    pdf.raise_window(shortp, job.get_pid(ppath))
end

return M
