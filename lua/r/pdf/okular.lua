local M = {}

local OkularJobStdout = function (_, data, _)
    for _, cmd in ipairs(data) do
        if vim.startswith(cmd, "call ") then
            vim.cmd(cmd)
        end
    end
end

M.open = function (fullpath)
        vim.g.rplugin.jobs["OkularSyncTeX"] = vim.fn.jobstart(
        {
            "okular",
            "--unique",
            "--editor-cmd",
            "echo 'call SyncTeX_backward(\"%f\", \"%l\")'",
            fullpath
        },
        {
            detach = true,
            on_stdout = vim.schedule_wrap(function(job_id, data, event_type)
                OkularJobStdout(job_id, data, event_type)
            end)
        }
    )
    if vim.g.rplugin.jobs["Okular"] < 1 then
        vim.notify("Failed to run Okular...")
    end
end

M.SyncTeX_forward = function (tpath, ppath, texln, _)
    local texname = vim.fn.substitute(tpath, ' ', '\\ ', 'g')
    local pdfname = vim.fn.substitute(ppath, ' ', '\\ ', 'g')
    vim.g.rplugin.jobs["OkularSyncTeX"] = vim.fn.jobstart(
        {
            "okular",
            "--unique",
            "--editor-cmd",
            "echo 'call SyncTeX_backward(\"%f\", \"%l\")'",
            pdfname .. "#src:" .. texln .. texname
        },
        {
            detach = true,
            on_stdout = vim.schedule_wrap(function(job_id, data, event_type)
                OkularJobStdout(job_id, data, event_type)
            end)
        }
    )
    if vim.g.rplugin.jobs["OkularSyncTeX"] < 1 then
        vim.notify("Failed to run Okular (SyncTeX forward)...")
    end
    if vim.g.rplugin.has_awbt then
        vim.fn.RRaiseWindow(pdfname)
    end
end

return M
