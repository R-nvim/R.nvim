
local config = require("r.config").get_config()
local warn = require("r").warn
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
        vim.o.filetype == "quarto" or vim.o.filetype == "rhelp" then
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
    local info = {}
    for k, v in pairs(debug_info) do
        if type(v) == "string" then
            table.insert(info, {tostring(k), "Title"})
            table.insert(info, {": "})
            if #v > 0 then
                table.insert(info, {v .. "\n"})
            else
                table.insert(info, {"(empty)\n"})
            end
        elseif type(v) == "table" then
            table.insert(info, {tostring(k), "Title"})
            table.insert(info, {":\n"})
            for vk, vv in pairs(v) do
                table.insert(info, {"  " .. tostring(vk), "Identifier"})
                table.insert(info, {": "})
                if tostring(k) == "Time" then
                    table.insert(info, {tostring(vv) .. "\n", "Number"})
                elseif tostring(k) == "nvimcom info" then
                    table.insert(info, {tostring(vv) .. "\n", "String"})
                else
                    table.insert(info, {tostring(vv) .. "\n"})
                end
            end
        else
            warn("debug_info error: " .. type(v))
        end
        -- vim.notify("Empty: " .. tostring(k) .. " " .. tostring(v))
    end
    vim.api.nvim_echo(info, false, {})
end

M.add_to_debug_info = function(title, info, parent)
    if parent then
        if debug_info[parent] == nil then
            debug_info[parent] = {}
        end
        debug_info[parent][title] = info
    else
        debug_info[title] = info
    end
end

M.get_debug_info = function ()
    return debug_info
end

M.raise_window = function(ttl)
    vim.fn.RRaiseWindow(ttl)
end

M.build_tags = function ()
    if vim.fn.filereadable("etags") then
        warn('The file "etags" exists. Please, delete it and try again.')
        return
    end
    require("r.send").cmd('rtags(ofile = "etags"); etags2ctags("etags", "tags"); unlink("etags")')
end

return M
