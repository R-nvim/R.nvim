local warn = require("r").warn
local pdf = require("r.pdf")
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
    local texname = vim.fn.substitute(tpath, " ", "\\ ", "g")
    local pdfname = vim.fn.substitute(ppath, " ", "\\ ", "g")
    local shortp = vim.fn.substitute(ppath, ".*/", "", "g")

    -- FIXME: this should not be necessary:
    ppath = ppath:gsub("//", "/")

    if not job.is_running(ppath) then
        M.open(ppath)
        -- Wait up to five seconds
        vim.wait(500)
        local i = 0
        while i < 45 do
            if job.is_running(ppath) then break end
            vim.wait(100)
            i = i + 1
        end
        if not job.is_running(ppath) then return end
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

    pdf.focus_window(shortp, job.get_pid(ppath))
end

return M
