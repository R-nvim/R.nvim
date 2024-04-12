local config = require("r.config").get_config()
local warn = require("r").warn
local del_list = {}
local rscript_buf = nil
local debug_info = { Time = {} }

local M = {}

M.assign = function()
    if vim.b.IsInRCode(false) then
        if config.assign_map == "_" then
            local line = vim.api.nvim_get_current_line()
            local pos = vim.api.nvim_win_get_cursor(0)
            if line:len() > 4 and line:sub(pos[2] - 3, pos[2]) == " <- " then
                line = line:sub(0, pos[2] - 4) .. "_" .. line:sub(pos[2] + 1, -1)
                vim.api.nvim_buf_set_lines(0, pos[1] - 1, pos[1], true, { line })
                vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] - 3 })
                return
            end
        end
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
        rscript_buf = vim.api.nvim_get_current_buf()
    end
end

--- Get the number of R script buffer
---@return number
M.get_rscript_buf = function() return rscript_buf end

-- Store list of files to be deleted on VimLeave
M.add_for_deletion = function(fname)
    for _, fn in ipairs(del_list) do
        if fn == fname then return end
    end
    table.insert(del_list, fname)
end

M.vim_leave = function()
    if vim.g.R_Nvim_status == 7 and config.auto_quit then
        require("r.run").quit_R("nosave")
        local i = 30
        while i > 0 and vim.g.R_Nvim_status == 7 do
            vim.wait(100)
            i = i - 1
        end
    end
    require("r.job").stop_rns()

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

--- Add item to debug info
---@param title string|table
---@param info string|number|table
---@param parent? string parent item
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
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(0, lnum, lnum, true, lines)
end

-- This function is called by nvimcom::vi(object).
-- The output of dput(object) is saved in fnm and R waits for the deletion of
-- fnm_wait.
---@param fnm string
M.obj = function(fnm)
    vim.schedule(function()
        vim.cmd({ cmd = "tabnew", args = { fnm } })
        vim.api.nvim_set_option_value("filetype", "r", { scope = "local" })
        vim.api.nvim_set_option_value("bufhidden", "wipe", { scope = "local" })
        vim.cmd("stopinsert")
        vim.api.nvim_create_autocmd("BufUnload", {
            command = "lua vim.loop.fs_unlink('" .. fnm .. "_wait')",
            pattern = "<buffer>",
        })
    end)
end

--- Display output sent by nvimcom
---@param fnm string File name
---@param txt string Text to display
M.get_output = function(fnm, txt)
    txt = txt:gsub("\019", "'")
    local lines = vim.split(txt, "\020")
    vim.cmd("tabnew " .. fnm)
    vim.api.nvim_buf_set_lines(0, 0, -1, true, lines)
    vim.cmd("normal! gT")
end

--- Displays the contents of a data.frame or matrix sent by nvimcom.
---@param oname string The name of the data.frame or matrix.
---@param howto string How to display.
---@param txt string The concatenated lines to be displayed.
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

--- Called by nvimcom. Displays the "Examples" section of R documentation.
M.open_example = function()
    local bl = vim.api.nvim_list_bufs()
    for _, v in pairs(bl) do
        if vim.api.nvim_buf_get_name(v) == config.tmpdir .. "/example.R" then
            vim.cmd("bunload! " .. tostring(v))
            break
        end
    end

    if config.nvimpager == "tabnew" or config.nvimpager == "tab" then
        vim.cmd("tabnew " .. config.tmpdir:gsub(" ", "\\ ") .. "/example.R")
    else
        local nvimpager = config.nvimpager
        if config.nvimpager == "split_v" then
            local wwidth = vim.fn.winwidth(0)
            local min_e = (config.editor_w > 78) and config.editor_w or 78
            local min_h = (config.help_w > 78) and config.help_w or 78
            if wwidth < (min_e + min_h) then nvimpager = "split_h" end
        end
        if nvimpager == "split_v" then
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
