local config = require("r.config").get_config()
local warn = require("r").warn
local del_list = {}
local rscript_name = "undefined"
local debug_info = { Time = {} }

local M = {}

M.assign = function()
    if vim.b.IsInRCode(false) then
        vim.fn.feedkeys(" <- ", "n")
    else
        vim.fn.feedkeys(config.assign_map, "n")
    end
end

M.buf_enter = function()
    if
        vim.o.filetype == "r"
        or vim.o.filetype == "rnoweb"
        or vim.o.filetype == "rmd"
        or vim.o.filetype == "quarto"
        or vim.o.filetype == "rhelp"
    then
        rscript_name = vim.fn.bufname("%")
    end
end

M.get_rscript_name = function() return rscript_name end

-- Store list of files to be deleted on VimLeave
M.add_for_deletion = function(fname)
    for _, fn in ipairs(del_list) do
        if fn == fname then return end
    end
    table.insert(del_list, fname)
end

M.vim_leave = function()
    require("r.job").stop_nrs()

    for _, fn in pairs(del_list) do
        vim.fn.delete(fn)
    end

    -- There is no need to check if `rmdir` is executable because it's
    -- available in every system: https://en.wikipedia.org/wiki/Rmdir
    vim.fn.jobstart("rmdir '" .. config.tmpdir .. "'", { detach = true })
    if config.localtmpdir ~= config.tmpdir then
        vim.fn.jobstart("rmdir '" .. config.localtmpdir .. "'", { detach = true })
    end
end

M.show_debug_info = function()
    local info = {}
    for k, v in pairs(debug_info) do
        if type(v) == "string" then
            table.insert(info, { tostring(k), "Title" })
            table.insert(info, { ": " })
            if #v > 0 then
                table.insert(info, { v .. "\n" })
            else
                table.insert(info, { "(empty)\n" })
            end
        elseif type(v) == "table" then
            table.insert(info, { tostring(k), "Title" })
            table.insert(info, { ":\n" })
            for vk, vv in pairs(v) do
                table.insert(info, { "  " .. tostring(vk), "Identifier" })
                table.insert(info, { ": " })
                if tostring(k) == "Time" then
                    table.insert(info, { tostring(vv) .. "\n", "Number" })
                elseif tostring(k) == "nvimcom info" then
                    table.insert(info, { tostring(vv) .. "\n", "String" })
                else
                    table.insert(info, { tostring(vv) .. "\n" })
                end
            end
        else
            warn("debug_info error: " .. type(v))
        end
    end
    vim.schedule(function() vim.api.nvim_echo(info, false, {}) end)
end

M.add_to_debug_info = function(title, info, parent)
    if parent then
        if debug_info[parent] == nil then debug_info[parent] = {} end
        debug_info[parent][title] = info
    else
        debug_info[title] = info
    end
end

M.build_tags = function()
    if vim.fn.filereadable("etags") then
        warn('The file "etags" exists. Please, delete it and try again.')
        return
    end
    require("r.send").cmd(
        'rtags(ofile = "etags"); etags2ctags("etags", "tags"); unlink("etags")'
    )
end

--- Receive formatted code from the nvimcom and change the buffer accordingly
---@param lnum1 number First selected line of unformatted code.
---@param lnum2 number Last selected line of unformatted code.
---@param txt string Formatted text.
M.finish_code_formatting = function(lnum1, lnum2, txt)
    local lns = vim.split(txt, "\020")
    vim.api.nvim_buf_set_lines(0, lnum1 - 1, lnum2, true, lns)
    vim.schedule(
        function()
            vim.api.nvim_echo(
                { { tostring(lnum2 - lnum1 + 1) .. " lines formatted." } },
                false,
                {}
            )
        end
    )
end

M.finish_inserting = function(type, txt)
    local lns = vim.split(txt, "\020")
    local lines
    if type == "comment" then
        lines = {}
        for _, v in pairs(lns) do
            table.insert(lines, "# " .. v)
        end
    else
        lines = lns
    end
    vim.api.nvim_buf_set_lines(0, vim.fn.line("."), vim.fn.line("."), true, lines)
end

-- This function is called by nvimcom
M.obj = function(fname)
    local fcont = vim.fn.readfile(fname)
    vim.cmd({ cmd = "tabnew", args = config.tmpdir .. "/edit_" .. vim.env.RNVIM_ID })
    vim.fn.setline(vim.fn.line("."), fcont)
    vim.api.nvim_set_option_value("filetype", "r", { scope = "local" })
    vim.cmd("stopinsert")
    vim.cmd(
        "autocmd BufUnload <buffer> lua require('os').remove('"
            .. config.tmpdir
            .. "/edit_"
            .. vim.env.RNVIM_ID
            .. "_wait')"
    )
end

M.get_output = function(fnm, txt)
    vim.cmd("tabnew " .. fnm)
    vim.fn.setline(1, vim.split(txt:gsub("\019", "'"), "\020"))
    vim.cmd("normal! gT")
end

M.view_df = function(oname, howto, txt)
    local csv_lines = vim.split(string.gsub(txt, "\019", "'"), "\020")
    local tsvnm = config.tmpdir .. "/" .. oname .. ".tsv"

    vim.fn.writefile(csv_lines, tsvnm)
    M.add_for_deletion(tsvnm)

    if type(config.csv_app) == "function" then
        config.csv_app(tsvnm, txt)
        return
    end

    if config.csv_app ~= "" then
        local cmd
        if config.csv_app:find("%%s") then
            cmd = string.format(config.csv_app, tsvnm)
        else
            cmd = config.csv_app .. " " .. tsvnm
        end

        if config.csv_app:find("^terminal:") then
            cmd = string.gsub(cmd, "^terminal:", "")
            vim.cmd("tabnew | terminal " .. cmd)
            vim.cmd("startinsert")
            return
        end

        if config.csv_app:find("^:") then
            vim.cmd(config.csv_app .. " " .. tsvnm)
            return
        end

        local appcmd = vim.fn.split(cmd)
        require("r.job").start("CSV app", appcmd, { detach = true })
        return
    end

    if howto == "head" then
        -- head() of data.frame
        vim.cmd("above")
        vim.cmd("7split " .. oname)
    else
        vim.api.nvim_cmd({ cmd = howto, args = { oname } }, {})
    end
    vim.api.nvim_set_option_value("modifiable", true, { scope = "local" })
    vim.api.nvim_buf_set_lines(0, 0, 1, true, csv_lines)
    vim.api.nvim_set_option_value("modifiable", false, { scope = "local" })
    vim.api.nvim_set_option_value("buftype", "nofile", { scope = "local" })
    vim.api.nvim_set_option_value("filetype", "csv", { scope = "local" })
end

M.open_example = function()
    if vim.fn.bufloaded(config.tmpdir .. "/example.R") ~= 0 then
        vim.cmd("bunload! " .. config.tmpdir:gsub(" ", "\\ "))
    end
    if config.nvimpager == "tabnew" or config.nvimpager == "tab" then
        vim.cmd("tabnew " .. config.tmpdir:gsub(" ", "\\ ") .. "/example.R")
    else
        local nvimpager = config.nvimpager
        if config.nvimpager == "vertical" then
            local wwidth = vim.fn.winwidth(0)
            local min_e = (config.editor_w > 78) and config.editor_w or 78
            local min_h = (config.help_w > 78) and config.help_w or 78
            if wwidth < (min_e + min_h) then nvimpager = "horizontal" end
        end
        if nvimpager == "vertical" then
            vim.cmd(
                "belowright vsplit " .. config.tmpdir:gsub(" ", "\\ ") .. "/example.R"
            )
        else
            vim.cmd("belowright split " .. config.tmpdir:gsub(" ", "\\ ") .. "/example.R")
        end
    end
    vim.api.nvim_buf_set_keymap(0, "n", "q", ":q<CR>", { noremap = true, silent = true })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { scope = "local" })
    vim.api.nvim_set_option_value("swapfile", false, { scope = "local" })
    vim.api.nvim_set_option_value("buftype", "nofile", { scope = "local" })
    vim.fn.delete(config.tmpdir .. "/example.R")
end

return M
