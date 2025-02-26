local config = require("r.config").get_config()
local get_lang = require("r.utils").get_lang
local warn = require("r.log").warn
local del_list = {}
local rscript_buf = 0
local debug_info = { Time = {} }
local assign_key = nil
local pipe_key = nil

local M = {}

M.assign = function()
    if not assign_key then
        assign_key = require("r.utils").get_mapped_key("RInsertAssign")
    end
    if get_lang() == "r" then
        if assign_key == "_" then
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
        vim.fn.feedkeys(tostring(assign_key), "n")
    end
end

M.pipe = function()
    local pipe_opts = {
        native = " |> ",
        ["|>"] = " |> ",
        magrittr = " %>% ",
        ["%>%"] = " %>% ",
    }

    local var_exists, buf_pipe_version = pcall(
        function() return vim.api.nvim_buf_get_var(0, "rnvim_pipe_version") end
    )
    if not var_exists then buf_pipe_version = nil end

    local pipe_version = buf_pipe_version or config.pipe_version
    local pipe_symbol = pipe_opts[pipe_version]

    if not pipe_key then pipe_key = require("r.utils").get_mapped_key("RInsertPipe") end

    if get_lang() == "r" then
        vim.fn.feedkeys(pipe_symbol, "n")
    else
        vim.fn.feedkeys(tostring(pipe_key), "n")
    end

    ---------------------------------------------------------------------------
    -- The next bit is something fancy to delete trailing whitespace if the
    -- user goes to a new line directly after inserting a pipe
    ---------------------------------------------------------------------------

    -- Remap a linebreak to delete a single trailing space before moving the
    -- cursor down. NB, there are several ways to insert a linebreak in insert
    -- mode.
    local temp_remaps = { "<CR>", "<C-j>" }

    for _, key in pairs(temp_remaps) do
        vim.keymap.set("i", key, function()
            local row, col = unpack(vim.api.nvim_win_get_cursor(0))
            -- Delete the trailing whitespace
            vim.api.nvim_buf_set_text(0, row - 1, col - 1, row - 1, col, {})
            -- Move the cursor back one column. This only makes a difference if
            -- a pipe has been inserted mid-line
            vim.api.nvim_win_set_cursor(0, { row, col - 1 })
            -- Delete this keymapping so whitespace stripping doesn't happen again
            vim.keymap.del("i", key, { buffer = 0 })
            -- Insert the newline
            vim.api.nvim_input(key)
        end, { buffer = 0 })
    end

    -- Set a single-use autocommand so that if the user changes the text, i.e.
    -- keeps typing after inserting the pipe, the above keymappings are removed
    vim.schedule(function()
        vim.api.nvim_create_autocmd({ "TextChangedI", "CursorMovedI", "InsertLeave" }, {
            once = true,
            callback = function()
                for _, key in pairs(temp_remaps) do
                    pcall(vim.keymap.del, "i", key, { buffer = 0 })
                end
            end,
        })
    end)
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
    if vim.o.filetype == "rmd" or vim.o.filetype == "quarto" then
        require("r.rmd").update_params()
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
    if vim.fn.filereadable("etags") == 1 then
        warn('The file "etags" exists. Please, delete it and try again.')
        return
    end
    require("r.send").cmd(
        'rtags(ofile = "etags"); etags2ctags("etags", "tags"); unlink("etags")'
    )
end

--- Reload the current buffer. Called by nvimcom after formatting a file.
M.reload = function() vim.cmd("edit %") end

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
            command = "lua vim.uv.fs_unlink('" .. fnm .. "_wait')",
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
---@param txt string The concatenated lines to be displayed.
M.view_df = function(oname, txt)
    local csv_lines
    if config.view_df.save_fun and config.view_df.save_fun ~= "" then
        if vim.fn.filereadable(txt) == 0 then
            warn('File "' .. txt .. '" not found.')
            return
        end
    else
        csv_lines = vim.split(string.gsub(txt, "\019", "'"), "\020")
    end

    local how = config.view_df.how or "tabnew"
    local open_app = config.view_df.open_app or ""
    local fname
    if config.view_df.save_fun and config.view_df.save_fun ~= "" then
        fname = txt
    else
        fname = oname
    end

    if open_app == "" then
        if vim.fn.bufloaded(fname) == 1 then
            local sbopt = vim.o.switchbuf
            vim.o.switchbuf = "useopen,usetab"
            vim.cmd.sb(fname)
            vim.o.switchbuf = sbopt
            vim.api.nvim_set_option_value("modified", false, { scope = "local" })
            if config.view_df.save_fun and config.view_df.save_fun ~= "" then
                vim.api.nvim_buf_set_lines(0, 0, -1, true, {})
                vim.cmd("edit " .. txt)
            else
                vim.api.nvim_set_option_value("modifiable", true, { scope = "local" })
                vim.api.nvim_buf_set_lines(0, 0, -1, true, csv_lines)
            end
        else
            vim.api.nvim_cmd({ cmd = how, args = { fname } }, {})
            if not (config.view_df.save_fun and config.view_df.save_fun ~= "") then
                vim.api.nvim_buf_set_lines(0, 0, -1, true, csv_lines)
            end
        end
        if fname:lower():find("%.tsv") or fname:lower():find("%.csv") then
            vim.api.nvim_set_option_value("filetype", "csv", { scope = "local" })
        end
        vim.api.nvim_set_option_value("bufhidden", "wipe", { scope = "local", buf = 0 })
        vim.api.nvim_set_option_value("swapfile", false, { scope = "local" })
        vim.api.nvim_set_option_value("buftype", "nofile", { scope = "local" })
        vim.api.nvim_set_option_value("modifiable", false, { scope = "local" })
        return
    end

    local tsvnm
    if config.view_df.save_fun and config.view_df.save_fun ~= "" then
        tsvnm = txt
    else
        tsvnm = config.tmpdir .. "/" .. oname .. ".tsv"
        vim.fn.writefile(csv_lines, tsvnm)
    end
    M.add_for_deletion(tsvnm)

    local cmd
    if open_app:find("%%s") then
        cmd = string.format(open_app, tsvnm)
    else
        cmd = open_app .. " " .. tsvnm
    end

    if open_app:find("^terminal:") then
        cmd = string.gsub(cmd, "^terminal:", "")
        vim.cmd(how .. " | terminal " .. cmd)
        vim.cmd("startinsert")
        return
    end

    if open_app:find("^:") then
        vim.cmd(cmd)
        return
    end

    local appcmd = vim.fn.split(cmd)
    require("r.job").start("CSV app", appcmd, { detach = true })
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
        if config.nvimpager == "split_v" then
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
