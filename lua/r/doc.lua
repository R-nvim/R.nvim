local config = require("r.config").get_config()
local send_to_nvimcom = require("r.run").send_to_nvimcom
local warn = require("r").warn
local cursor = require("r.cursor")
local rdoctitle = "R_doc"

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

    local htw = vim.o.columns > 80 and 80 or vim.o.columns - 1
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
    if
        not config.nvimpager:find("tab")
        and not config.nvimpager:find("split")
        and not config.nvimpager:find("float")
        and not config.nvimpager:find("no")
    then
        warn(
            'Invalid `nvimpager` value: "'
                .. config.nvimpager
                .. '". Valid values are: "tab", "split", "float", and "no".'
        )
        return
    end

    -- Check if `nvimpager` is "no" because the user might have set the pager
    -- in the .Rprofile.
    local vpager
    if config.nvimpager == "no" then
        if type(config.external_term) == "boolean" and not config.external_term then
            vpager = "split"
        else
            vpager = "tab"
        end
    else
        vpager = config.nvimpager
    end

    local htw = vim.o.columns > 80 and 80 or vim.o.columns - 1
    if rkeyword:match("^MULTILIB") then
        local topic = vim.fn.split(rkeyword, " ")[2]
        local libs = vim.fn.split(txt, "\024")
        local msg = "The topic '" .. topic .. "' was found in more than one library:\n"
        for idx, lib in ipairs(libs) do
            msg = msg .. idx .. " : " .. lib .. "\n"
        end
        vim.cmd("redraw")
        -- FIXME: not working:
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

    local rdoccaption = rkeyword:gsub("\\", "")
    if rkeyword:match("R History") then
        rdoccaption = "R_History"
        rdoctitle = "R_History"
    end

    if vim.fn.bufloaded(rdoccaption) == 1 then
        local savesb = vim.o.switchbuf
        vim.o.switchbuf = "useopen,usetab"
        vim.cmd.sb(rdoctitle)
        vim.cmd("set switchbuf=" .. savesb)
    else
        if vpager == "tab" or vpager == "float" then
            vim.cmd("tabnew " .. rdoctitle)
        else
            if vim.fn.winwidth(0) < 80 then
                vim.cmd("topleft split " .. rdoctitle)
            else
                vim.cmd("split " .. rdoctitle)
            end
            if vim.fn.winheight(0) < 10 then vim.cmd("resize 20") end
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

--- Load HTML document
---@param fullpath string
---@param browser string
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
        cmd = vim.split(browser, " ")
        table.insert(cmd, fullpath)
    end

    require("r.job").start("HTML browser", cmd, { detach = 1 })
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
