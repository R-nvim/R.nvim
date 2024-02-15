local evince_list = {}
local py = nil
local evince_loop = 0
local config = require("r.config").get_config()
local rnw = require("r.rnw")
local job = require("r.job")
local pdf = require("r.pdf")

-- Check if python3 is executable, otherwise use python
if vim.fn.executable("python3") > 0 then
    py = "python3"
else
    py = "python"
end

local M = {}

M.open = function(fullpath)
    if job.is_running(fullpath) then
        local fname = fullpath:gsub(".*/", "")
        pdf.focus_window(fname, job.get_pid(fullpath))
        return
    end

    local eopts = {
        on_stdout = require("r.job").on_stdout,
        on_exit = require("r.job").on_exit,
        detach = true,
    }

    local ecmd = { "evince", fullpath }
    job.start(fullpath, ecmd, eopts)
end

M.SyncTeX_forward = function(tpath, ppath, texln)
    local n1 = tpath:gsub("(^/.*/).*", "%1")
    local n2 = tpath:gsub(".*/(.*)", "%1")
    local texname = n1:gsub(" ", "%20") .. n2
    local pdfname = ppath:gsub(" ", "%20")

    if evince_loop < 2 then
        require("r.job").start("Python (Evince forward)", {
            py,
            config.rnvim_home .. "/scripts/pdf_evince_forward.py",
            texname,
            pdfname,
            tostring(texln),
        }, nil)
    else
        evince_loop = 0
    end
    require("r.pdf").focus_window(ppath:gsub(".*/", ""), job.get_pid(ppath))
end

M.run_evince_SyncTeX_server = function()
    local basenm = rnw.SyncTeX_get_master() .. ".pdf"
    if not vim.b.rplugin_pdfdir then require("r.rnw").set_pdf_dir() end
    local pdfpath = vim.b.rplugin_pdfdir .. "/" .. basenm:gsub(".*/", "")
    local did_evince = 0

    for _, bb in ipairs(evince_list) do
        if bb == pdfpath then
            did_evince = 1
            break
        end
    end

    if did_evince == 0 then
        table.insert(evince_list, pdfpath)
        require("r.job").start(
            "Python (Evince backward)",
            { py, config.rnvim_home .. "/scripts/pdf_evince_back.py", pdfpath },
            nil
        )
    end
end

-- Avoid possible infinite loop
M.again = function()
    evince_loop = evince_loop + 1
    rnw.SyncTeX_forward()
end

return M
