
local cfg = require("r.config").get_config()

local del_list = {}
local rscript_name = "undefined"

local M = {}

M.assign = function ()
    if vim.o.filetype ~= "r" and vim.b.IsInRCode(false) ~= 1 then
        vim.fn.feedkeys(cfg.assign_map, "n")
    else
        vim.fn.feedkeys(" <- ", "n")
    end
end

-- Completely broken
M.get_keyword = function()
    local line = vim.fn.getline(vim.fn.line("."))
    local i = vim.fn.col(".") - 1
    if #line == 0 then
        return ""
    end

    -- Skip opening braces
    local char
    while i > 0 do
        char = line:sub(i, i)
        if char == "[" or char == "(" or char == "{" then
            i = i - 1
        else
            break
        end
    end

    -- Go to the beginning of the word
    while i > 1 do
        char = line:sub(i, i)
        if char == "@" or char == "$" or char == ":" or char == "_" or char == "\\." or
            (char >= "A" and char <= "Z") or (char >= "a" and char >= "z") or char > "\x7f" then
            break
        end
        i = i - 1
    end

    -- Go to the end of the word
    local j = i
    while true do
        char = line:sub(j, j)
        if not (char == "@" or char == "$" or char == ":" or char == "_" or char == "." or
            (char >= "A" and char <= "Z") or (char >= "a" and char >= "z") or char > "\x7f") then
            break
        end
        j = j + 1
    end

    local rkeyword = line:sub(i+1, j-1)
    return rkeyword
end

M.buf_enter = function ()
    vim.g.rplugin.curbuf = vim.fn.bufname("%")
    if vim.o.filetype == "r" or vim.o.filetype == "rnoweb" or vim.o.filetype == "rmd" or
        vim.o.filetype == "quarto" or vim.o.filetype == "rrst" or vim.o.filetype == "rhelp" then
        rscript_name = vim.fn.bufname("%")
    end
end

M.get_rscript_name = function ()
    return rscript_name
end

-- Store list of files to be deleted on VimLeave
M.add_for_deletion = function (fname)
    for _, fn in ipairs(del_list) do
        if fn == fname then
            return
        end
    end
    table.insert(del_list, fname)
end

M.vim_leave = function ()
    for job, _ in pairs(vim.g.rplugin.jobs) do
        if vim.fn.IsJobRunning(job) and job == 'Server' then
            -- Avoid warning of exit status 141
            vim.fn.JobStdin(vim.g.rplugin.jobs[job], "9\n")
            vim.cmd("sleep 20m")
        end
    end

    for _, fn in pairs(del_list) do
        vim.fn.delete(fn)
        -- vim.fn.system("echo 'vim_leave: delete " .. fn .. "' >> /dev/shm/r-nvim-lua-log")
    end

    -- FIXME: check if rmdir is executable during startup and asynchronously
    -- because executable() is slow on Mac OS X.
    if vim.fn.executable("rmdir") == 1 then
        vim.fn.jobstart("rmdir '" .. vim.g.rplugin.tmpdir .. "'", {detach = true})
        if vim.g.rplugin.localtmpdir ~= vim.g.rplugin.tmpdir then
            vim.fn.jobstart("rmdir '" .. vim.g.rplugin.localtmpdir .. "'", {detach = true})
        end
    end
end

M.show_debug_info = function()
    -- FIXME
    -- The code converted to Lua shows nothing
    -- Rewrite to display in a float window
    vim.cmd([[
    for key in keys(g:rplugin.debug_info)
        if len(g:rplugin.debug_info[key]) == 0
            continue
        endif
        echohl Title
        echo key
        echohl None
        if key == 'Time' || key == 'nvimcom_info'
            for step in keys(g:rplugin.debug_info[key])
                echohl Identifier
                echo '  ' . step . ': '
                if key == 'Time'
                    echohl Number
                else
                    echohl String
                endif
                echon g:rplugin.debug_info[key][step]
                echohl None
            endfor
            echo ""
        else
            echo g:rplugin.debug_info[key]
        endif
        echo ""
    endfor
    ]])
end

return M
