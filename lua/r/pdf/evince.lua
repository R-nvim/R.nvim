local evince_list = {}
local py = nil
local evince_loop = 0
local config = require("r.config").get_config()
local rnw = require("r.rnw")

-- Check if python3 is executable, otherwise use python
if vim.fn.executable("python3") > 0 then
    py = "python3"
else
    py = "python"
end

local M = {}

M.open = function(fullpath)
    local pcmd = "evince '" .. fullpath .. "' 2>/dev/null >/dev/null &"
    vim.fn.system(pcmd)
end

M.SyncTeX_forward = function(tpath, ppath, texln, _)
    local n1 = vim.fn.substitute(tpath, "\\(^/.*/\\).*", "\\1", "")
    local n2 = vim.fn.substitute(tpath, ".*/\\(.*\\)", "\\1", "")
    local texname = vim.fn.substitute(n1, " ", "%20", "g") .. n2
    local pdfname = vim.fn.substitute(ppath, " ", "%20", "g")

    if evince_loop < 2 then
        require("r.job").start("Python (Evince forward)", {
            py,
            config.rnvim_home .. "/R/pdf_evince_forward.py",
            texname,
            pdfname,
            tostring(texln),
        }, nil)
    else
        evince_loop = 0
    end
    require("r.pdf").raise_window(string.gsub(ppath, ".*/", ""))
end

M.SyncTeX_backward = function()
    local basenm = rnw.SyncTeX_GetMaster() .. ".pdf"
    local pdfpath = vim.b.rplugin_pdfdir
        .. "/"
        .. vim.fn.substitute(basenm, ".*/", "", "")
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
            { py, config.rnvim_home .. "/R/pdf_evince_back.py", pdfpath },
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
