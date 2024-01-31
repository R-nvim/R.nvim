
local config = require("r.config").get_config()

local del_list = {}
local rscript_name = "undefined"
local debug_info = {Time = {}}

local M = {}

M.assign = function ()
    if vim.o.filetype ~= "r" and vim.b.IsInRCode(false) ~= 1 then
        vim.fn.feedkeys(config.assign_map, "n")
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
    require("r.job").stop_nrs()

    for _, fn in pairs(del_list) do
        vim.fn.delete(fn)
    end

    -- FIXME: check if rmdir is executable during startup and asynchronously
    -- because executable() is slow on Mac OS X.
    if vim.fn.executable("rmdir") == 1 then
        vim.fn.jobstart("rmdir '" .. config.tmpdir .. "'", {detach = true})
        if config.localtmpdir ~= config.tmpdir then
            vim.fn.jobstart("rmdir '" .. config.localtmpdir .. "'", {detach = true})
        end
    end
end

M.show_debug_info = function()
    -- FIXME
    -- The code with "echo" commands converted to Lua shows nothing
    -- Rewrite to display in a float window
    local dstr = ""
    for k, v in pairs(debug_info) do
        dstr = dstr .. tostring(k) .. ":\n"
        if #v > 0 then
            if type(v) == "string" then
                dstr = dstr .. tostring(v) .. "\n"
            else
                for vk, vv in pairs(v) do
                    dstr = dstr .. "  " .. tostring(vk) ": "
                    dstr = dstr .. tostring(vv) .. "\n"
                end
            end
        end
    end
    print(dstr)
end

M.get_debug_info = function ()
    return debug_info
end

M.raise_window = function(ttl)
    vim.fn.RRaiseWindow(ttl)
end

return M
