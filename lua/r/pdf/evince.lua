local evince_list = {}
local py = nil

-- Check if python3 is executable, otherwise use python
if vim.fn.executable('python3') > 0 then
    py = 'python3'
else
    py = 'python'
end

local M = {}

M.open = function (fullpath)
    local pcmd = "evince '" .. fullpath .. "' 2>/dev/null >/dev/null &"
    vim.fn.system(pcmd)
end

M.SyncTeX_forward = function (tpath, ppath, texln, _)
    local n1 = vim.fn.substitute(tpath, '\\(^/.*/\\).*', '\\1', '')
    local n2 = vim.fn.substitute(tpath, '.*/\\(.*\\)', '\\1', '')
    local texname = vim.fn.substitute(n1, " ", "%20", "g") .. n2
    local pdfname = vim.fn.substitute(ppath, " ", "%20", "g")

    if vim.g.rplugin.evince_loop < 2 then
        require("r.job").start(
            "Python (Evince forward)",
            { py, vim.g.rplugin.home .. "/R/pdf_evince_forward.py", texname, pdfname, tostring(texln) },
            nil
        )
    else
        vim.g.rplugin.evince_loop = 0
    end
    vim.fn.RRaiseWindow(vim.fn.substitute(ppath, ".*/", "", ""))
end

M.run_EvinceBackward = function ()
    local basenm = vim.fn.SyncTeX_GetMaster() .. ".pdf"
    local pdfpath = vim.b.rplugin_pdfdir .. "/" .. vim.fn.substitute(basenm, ".*/", "", "")
    local did_evince = 0

    if not evince_list then
        evince_list = {}
    else
        for _, bb in ipairs(evince_list) do
            if bb == pdfpath then
                did_evince = 1
                break
            end
        end
    end

    if did_evince == 0 then
        table.insert(evince_list, pdfpath)
        vim.g.rplugin.jobs["Python (Evince backward)"] = vim.fn.StartJob(
            { py, vim.g.rplugin.home .. "/R/pdf_evince_back.py", pdfpath },
            vim.g.rplugin.job_handlers
        )
    end
end

-- Avoid possible infinite loop
M.Evince_Again = function ()
    vim.g.rplugin.evince_loop = vim.g.rplugin.evince_loop + 1
    vim.fn.SyncTeX_forward()
end

return M
