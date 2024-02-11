local config = require("r.config").get_config()
local send_to_nvimcom = require("r.run").send_to_nvimcom
local warn = require("r").warn
local cursor = require("r.cursor")
local has_new_width = true
local rdoctitle = "R_doc"
local htw

local set_text_width = function(rkeyword)
    if config.nvimpager == "tabnew" then
        rdoctitle = rkeyword
    else
        local tnr = vim.fn.tabpagenr()
        if config.nvimpager ~= "tab" and tnr > 1 then
            rdoctitle = "R_doc" .. tnr
        else
            rdoctitle = "R_doc"
        end
    end

    if vim.fn.bufloaded(rdoctitle) == 0 or has_new_width == 1 then
        has_new_width = false

        -- s:vimpager is used to calculate the width of the R help documentation
        -- and to decide whether to obey R_nvimpager = 'vertical'
        local vimpager = config.nvimpager

        local wwidth = vim.fn.winwidth(0)

        -- Not enough room to split vertically
        if
            config.nvimpager == "vertical"
            and wwidth <= (config.help_w + config.editor_w)
        then
            vimpager = "horizontal"
        end

        local htwf
        if vimpager == "horizontal" then
            -- Use the window width (at most 80 columns)
            htwf = (wwidth > 80) and 88.1 or ((wwidth - 1) / 0.9)
        elseif config.nvimpager == "tab" or config.nvimpager == "tabnew" then
            wwidth = vim.o.columns
            htwf = (wwidth > 80) and 88.1 or ((wwidth - 1) / 0.9)
        else
            local min_e = (config.editor_w > 80) and config.editor_w or 80
            local min_h = (config.help_w > 73) and config.help_w or 73

            if wwidth > (min_e + min_h) then
                -- The editor window is large enough to be split
                htwf = min_h
            elseif wwidth > (min_e + config.help_w) then
                -- The help window must have less than min_h columns
                htwf = wwidth - min_e
            else
                -- The help window must have the minimum value
                htwf = config.help_w
            end
            htwf = (htwf - 1) / 0.9
        end

        htw = vim.fn.float2nr(htwf)
        if vim.wo.number == 1 or vim.wo.relativenumber == 1 then
            htw = htw - vim.o.numberwidth
        end
    end
end

local M = {}

M.ask_R_help = function(topic)
    if topic == "" then
        require("r.send").cmd("help.start()")
        return
    end
    if config.nvimpager == "no" then
        require("r.send").cmd("help(" .. topic .. ")")
    else
        M.ask_R_doc(topic, "", false)
    end
end

--- Request R documentation on an object
---@param rkeyword string The topic of the requested help
---@param package string Library of the object
---@param getclass boolean If the object is a function, whether R should check the class of the first argument passed to it to retrieve documentation on the appropriate method.
M.ask_R_doc = function(rkeyword, package, getclass)
    local firstobj = ""
    local R_bufnr = require("r.term").get_buf_nr()
    if vim.fn.bufname("%") == "Object_Browser" or vim.fn.bufnr("%") == R_bufnr then
        local savesb = vim.o.switchbuf
        vim.o.switchbuf = "useopen,usetab"
        vim.cmd.sb(require("r.edit").get_rscript_name())
        vim.cmd("set switchbuf=" .. savesb)
    else
        if getclass then firstobj = cursor.get_first_obj() end
    end

    set_text_width(rkeyword)

    local rcmd
    if firstobj == "" and package == "" then
        rcmd = 'nvimcom:::nvim.help("' .. rkeyword .. '", ' .. htw .. "L)"
    elseif package ~= "" then
        rcmd = 'nvimcom:::nvim.help("'
            .. rkeyword
            .. '", '
            .. htw
            .. 'L, package="'
            .. package
            .. '")'
    else
        rcmd = 'nvimcom:::nvim.help("'
            .. rkeyword
            .. '", '
            .. htw
            .. 'L, "'
            .. firstobj
            .. '")'
    end

    send_to_nvimcom("E", rcmd)
end

M.show = function(rkeyword, txt)
    if rkeyword:match("^MULTILIB") then
        local topic = vim.fn.split(rkeyword, " ")[2]
        local libs = vim.fn.split(txt, "\024")
        local msg = "The topic '" .. topic .. "' was found in more than one library:\n"
        for idx, lib in ipairs(libs) do
            msg = msg .. idx .. " : " .. lib .. "\n"
        end
        vim.cmd("redraw")
        local chn = vim.fn.input(msg .. "Please, select one of them: ")
        if tonumber(chn) and tonumber(chn) > 0 and tonumber(chn) <= #libs then
            send_to_nvimcom(
                "E",
                'nvimcom:::nvim.help("'
                    .. topic
                    .. '", '
                    .. htw
                    .. 'L, package="'
                    .. libs[tonumber(chn)]
                    .. '")'
            )
        end
        return
    end

    local R_bufnr = require("r.term").get_buf_nr()
    if vim.fn.bufnr("%") == R_bufnr then
        -- Exit Terminal mode and go to Normal mode
        vim.cmd("stopinsert")
    end

    if vim.fn.bufname("%"):match("Object_Browser") or vim.fn.bufnr("%") == R_bufnr then
        local savesb = vim.o.switchbuf
        vim.o.switchbuf = "useopen,usetab"
        vim.cmd.sb(require("r.edit").get_rscript_name())
        vim.cmd("set switchbuf=" .. savesb)
    end
    set_text_width(rkeyword)

    local rdoccaption = rkeyword:gsub("\\", "")
    if rkeyword:match("R History") then
        rdoccaption = "R_History"
        rdoctitle = "R_History"
    end

    if vim.fn.bufloaded(rdoccaption) == 1 then
        local curtabnr = vim.fn.tabpagenr()
        local savesb = vim.o.switchbuf
        vim.o.switchbuf = "useopen,usetab"
        vim.cmd.sb(rdoctitle)
        vim.cmd("set switchbuf=" .. savesb)
        if config.nvimpager == "tabnew" then vim.cmd("tabmove " .. curtabnr) end
    else
        if config.nvimpager == "tab" or config.nvimpager == "tabnew" then
            vim.cmd("tabnew " .. rdoctitle)
        elseif config.nvimpager == "vertical" then
            local splr = vim.o.splitright
            vim.o.splitright = true
            vim.cmd(htw .. "vsplit " .. rdoctitle)
            vim.o.splitright = splr
        elseif config.nvimpager == "horizontal" then
            vim.cmd("split " .. rdoctitle)
            if vim.fn.winheight(0) < 20 then vim.cmd("resize 20") end
        elseif config.nvimpager == "no" then
            if type(config.external_term) == "boolean" and not config.external_term then
                config.nvimpager = "vertical"
            else
                config.nvimpager = "tab"
            end
            M.show(rkeyword)
            return
        else
            warn(
                'Invalid `nvimpager` value: "'
                    .. config.nvimpager
                    .. '". Valid values are: "tab", "vertical", "horizontal", "tabnew" and "no".'
            )
            return
        end
    end

    vim.cmd("setlocal modifiable")

    local save_unnamed_reg = vim.fn.getreg("@@")
    vim.o.modifiable = true
    vim.cmd("silent normal! ggdG")
    txt = txt:gsub("\019", "'")
    local lines
    if txt:find("\008") then
        lines = require("r.rdoc").fix_rdoc(txt)
    else
        lines = vim.split(txt, "\020")
    end
    vim.fn.setline(1, lines)
    if rkeyword:match("R History") then
        vim.o.filetype = "r"
        vim.fn.cursor(1, 1)
    elseif rkeyword:match("(help)") or vim.fn.search("\008", "nw") > 0 then
        require("r.rdoc").set_buf_options()
        vim.fn.cursor(1, 1)
    elseif rkeyword:find("%.Rd$") then
        -- Called by devtools::load_all().
        -- See https://github.com/jalvesaq/Nvim-R/issues/482
        vim.o.filetype = "rhelp"
        vim.fn.cursor(1, 1)
    else
        vim.o.syntax = "rout"
        vim.cmd("setlocal bufhidden=wipe")
        vim.cmd("setlocal nonumber")
        vim.cmd("setlocal noswapfile")
        vim.o.buftype = "nofile"
        vim.api.nvim_buf_set_keymap(
            0,
            "n",
            "q",
            ":q<CR>",
            { noremap = true, silent = true }
        )
        vim.fn.cursor(1, 1)
    end
    vim.fn.setreg("@@", save_unnamed_reg)
    vim.cmd("setlocal nomodified")
    vim.cmd("stopinsert")
    vim.cmd("redraw")
end

M.load_html = function(fullpath, browser)
    if not config.openhtml then return end

    local cmd
    if browser == "" then
        if config.is_windows or config.is_darwin then
            cmd = { "open", fullpath }
        else
            cmd = { "xdg-open", fullpath }
        end
    else
        cmd = table.insert(vim.split(browser, " "), fullpath)
    end

    require("r.job").start()
    vim.fn.jobstart(cmd, { detach = 1 })
end

M.open = function(fullpath, browser)
    if fullpath == "" then return end
    if vim.fn.filereadable(fullpath) == 0 then
        warn('The file "' .. fullpath .. '" does not exist.')
        return
    end
    if fullpath:match(".odt$") or fullpath:match(".docx$") then
        vim.fn.system("lowriter " .. fullpath .. " &")
    elseif fullpath:match(".pdf$") then
        require("r.pdf").open(fullpath)
    elseif fullpath:match(".html$") then
        M.load_html(fullpath, browser)
    else
        warn("Unknown file type from nvim.interlace: " .. fullpath)
    end
end

return M
