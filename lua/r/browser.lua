local config = require("r.config").get_config()
local warn = require("r").warn
local job = require("r.job")
local send_to_nvimcom = require("r.run").send_to_nvimcom

local reserved =
    "\\%(if\\|else\\|repeat\\|while\\|function\\|for\\|in\\|next\\|break\\|TRUE\\|FALSE\\|NULL\\|Inf\\|NaN\\|NA\\|NA_integer_\\|NA_real_\\|NA_complex_\\|NA_character_\\)"

local punct =
    "\\(!\\|''\\|\"\\|#\\|%\\|&\\|(\\|)\\|*\\|+\\|,\\|-\\|/\\|\\\\\\|:\\|;\\|<\\|=\\|>\\|?\\|@\\|[\\|/\\|]\\|\\^\\|\\$\\|{\\||\\|}\\|\\~\\)"

local envstring = vim.fn.tolower(vim.env.LC_MESSAGES .. vim.env.LC_ALL .. vim.env.LANG)
local isutf8 = (envstring:find("utf-8") or envstring:find("utf8")) and 1 or 0
local curview = "GlobalEnv"
local ob_winnr
local ob_buf
local upobcnt = false
local running_objbr = false
local auto_starting = true

-- Popup menu
local hasbrowsermenu = false

-- Table for local functions that call themselves
local L = {}

local set_buf_options = function()
    vim.api.nvim_set_option_value("wrap", false, { scope = "local" })
    vim.api.nvim_set_option_value("list", false, { scope = "local" })
    vim.api.nvim_set_option_value("number", false, { scope = "local" })
    vim.api.nvim_set_option_value("relativenumber", false, { scope = "local" })
    vim.api.nvim_set_option_value("cursorline", false, { scope = "local" })
    vim.api.nvim_set_option_value("cursorcolumn", false, { scope = "local" })
    vim.api.nvim_set_option_value("spell", false, { scope = "local" })
    vim.api.nvim_set_option_value("winfixwidth", false, { scope = "local" })
    vim.api.nvim_set_option_value("swapfile", false, { scope = "local" })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { scope = "local" })
    vim.api.nvim_set_option_value("buftype", "nofile", { scope = "local" })
    vim.api.nvim_set_option_value("syntax", "rbrowser", { scope = "local" })
    vim.api.nvim_set_option_value("iskeyword", "@,48-57,_,.", { scope = "local" })

    local opts = { silent = true, noremap = true, expr = false }
    vim.api.nvim_buf_set_keymap(
        0,
        "n",
        "<CR>",
        "<Cmd>lua require('r.browser').on_double_click()<CR>",
        opts
    )
    vim.api.nvim_buf_set_keymap(
        0,
        "n",
        "<2-LeftMouse>",
        "<Cmd>lua require('r.browser').on_double_click()<CR>",
        opts
    )
    vim.api.nvim_buf_set_keymap(
        0,
        "n",
        "<RightMouse>",
        "<Cmd>lua require('r.browser').on_right_click()<CR>",
        opts
    )

    vim.api.nvim_create_autocmd("BufEnter", {
        command = "stopinsert",
        pattern = "<buffer>",
    })

    vim.api.nvim_create_autocmd("BufUnload", {
        command = "lua require('r.browser').on_BufUnload()",
        pattern = "<buffer>",
    })

    vim.fn.setline(1, ".GlobalEnv | Libraries")

    require("r.maps").create("rbrowser")
end

L.find_parent = function(word, curline, curpos)
    local line
    while curline > 1 and curpos >= curpos do
        curline = curline - 1
        line = vim.fn.substitute(vim.fn.getline(curline), "\x09.*", "", "")
        curpos = vim.fn.stridx(line, "[#")
        if curpos == -1 then
            curpos = vim.fn.stridx(line, "$#")
            if curpos == -1 then
                curpos = vim.fn.stridx(line, "<#")
                if curpos == -1 then curpos = curpos end
            end
        end
    end

    local spacelimit
    if curview == "GlobalEnv" then
        spacelimit = 3
    else
        spacelimit = isutf8 and 10 or 6
    end

    if curline > 1 then
        local suffix
        if vim.fn.match(line, " <#") > -1 then
            suffix = "@"
        else
            suffix = "$"
        end
        local thisword = vim.fn.substitute(line, "^.\\{-}#", "", "")
        if
            vim.fn.match(thisword, " ") > -1
            or vim.fn.match(thisword, "^[0-9_]") > -1
            or vim.fn.match(thisword, punct) > -1
        then
            thisword = "`" .. thisword .. "`"
        end
        word = thisword .. suffix .. word
        if curpos ~= spacelimit then word = L.find_parent(word, line("."), curpos) end
        return word
    else
        -- Didn't find the parent: should never happen.
        vim.notify(
            "R-Nvim Error: " .. word .. ":" .. curline,
            vim.log.levels.ERROR,
            { title = "R-Nvim" }
        )
    end
    return ""
end

-- Start Object Browser
L.start_OB = function()
    -- Either open or close the Object Browser
    local savesb = vim.o.switchbuf
    vim.o.switchbuf = "useopen,usetab"

    if vim.fn.bufloaded("Object_Browser") == 1 then
        local curwin = vim.fn.win_getid()
        local curtab = vim.fn.tabpagenr()
        vim.cmd.sb("Object_Browser")
        local objbrtab = vim.fn.tabpagenr()
        vim.cmd("quit")
        vim.fn.win_gotoid(curwin)

        if curtab ~= objbrtab then L.start_OB() end
    else
        local edbuf = vim.fn.bufnr()

        if config.objbr_place:find("RIGHT") then
            vim.cmd("botright vsplit Object_Browser")
        elseif config.objbr_place:find("LEFT") then
            vim.cmd("topleft vsplit Object_Browser")
        elseif config.objbr_place:find("TOP") then
            vim.cmd("topleft split Object_Browser")
        elseif config.objbr_place:find("BOTTOM") then
            vim.cmd("botright split Object_Browser")
        else
            if config.objbr_place:find("console") then
                vim.cmd.sb(require("r.term").get_buf_nr())
            else
                vim.cmd.sb(require("r.edit").get_rscript_name())
            end

            if config.objbr_place:find("right") then
                vim.cmd("rightbelow vsplit Object_Browser")
            elseif config.objbr_place:find("left") then
                vim.cmd("leftabove vsplit Object_Browser")
            elseif config.objbr_place:find("above") then
                vim.cmd("aboveleft split Object_Browser")
            elseif config.objbr_place:find("below") then
                vim.cmd("belowright split Object_Browser")
            else
                warn('Invalid value for R_objbr_place: "' .. config.objbr_place .. '"')
                vim.cmd("set switchbuf=" .. savesb)
                return
            end
        end

        if config.objbr_place:find("left") or config.objbr_place:find("right") then
            vim.cmd("vertical resize " .. config.objbr_w)
        else
            vim.cmd("resize " .. config.objbr_h)
        end

        set_buf_options()
        curview = "GlobalEnv"
        ob_winnr = vim.fn.winnr()
        ob_buf = vim.fn.bufnr()

        if config.objbr_auto_start and auto_starting then
            auto_starting = false
            vim.cmd.sb(edbuf)
        end
    end

    vim.cmd("set switchbuf=" .. savesb)
end

local M = {}

-- Open an Object Browser window
M.start = function(_)
    -- Only opens the Object Browser if R is running
    if vim.g.R_Nvim_status < 5 then
        warn("The Object Browser can be opened only if R is running.")
        return
    end

    if running_objbr then
        -- Called twice due to BufEnter event
        return
    end

    running_objbr = true

    -- call RealUpdateRGlbEnv(1)
    job.stdin("Server", "31\n")
    send_to_nvimcom("A", "RObjBrowser")

    L.start_OB()
    running_objbr = false

    if config.hook.after_ob_open then
        vim.fn.redraw()
        config.hook.after_ob_open()
    end
end

M.get_curview = function() return curview end

M.get_pkg_name = function()
    local lnum = vim.fn.line(".")
    while lnum > 0 do
        local line = vim.fn.getline(lnum)
        if vim.fn.match(line, ".*##[0-9a-zA-Z\\.]*\t") > -1 then
            return vim.fn.substitute(line, ".*##\\(.\\{-}\\)\t.*", "\\1", "")
        end
        lnum = lnum - 1
    end
    return ""
end

M.get_name = function()
    local line = vim.fn.getline(vim.fn.line("."))
    if vim.fn.match(line, "^$") > -1 or vim.fn.line(".") < 3 then return "" end

    local curpos = vim.fn.stridx(line, "#")
    local word = vim.fn.substitute(line, ".\\{-}\\(.#\\)\\(\\(.-\\)\\)\\t.*", "\\3", "")

    if
        vim.fn.match(word, " ") > -1
        or vim.fn.match(word, "^[0-9]") > -1
        or vim.fn.match(word, punct) > -1
        or vim.fn.match(word, "^" .. reserved .. "$") > -1
    then
        word = "`" .. word .. "`"
    end

    if curpos == 4 then
        -- top level object
        word = vim.fn.substitute(word, "\\$\\[\\[", "[[", "g")
        if curview == "libraries" then
            return word .. ":"
        else
            return word
        end
    else
        if curview == "libraries" then
            if isutf8 then
                if curpos == 11 then
                    word = vim.fn.substitute(word, "\\$\\[\\[", "[[", "g")
                    return word
                end
            elseif curpos == 7 then
                word = vim.fn.substitute(word, "\\$\\[\\[", "[[", "g")
                return word
            end
        end
        if curpos > 4 then
            -- Find the parent data.frame or list
            word = L.find_parent(word, vim.fn.line("."), curpos - 1)
            word = vim.fn.substitute(word, "\\$\\[\\[", "[[", "g")
            return word
        else
            -- Wrong object name delimiter: should never happen.
            local msg = "R-plugin Error: (curpos = " .. curpos .. ") " .. word
            vim.fn.echoerr(msg)
            return ""
        end
    end
end

M.open_close_lists = function(stt) job.stdin("Server", "34" .. stt .. curview .. "\n") end

M.update_OB = function(what)
    local wht = what == "both" and curview or what
    if curview ~= wht then return "curview != what" end
    if upobcnt then
        -- vim.api.nvim_err_writeln("OB called twice")
        return "OB called twice"
    end

    upobcnt = true

    local bufl = vim.fn.execute("buffers")
    if bufl:find("Object_Browser") == nil then
        upobcnt = false
        return "Object_Browser not listed"
    end

    local fcntt
    if wht == "GlobalEnv" then
        fcntt = vim.fn.readfile(config.localtmpdir .. "/globenv_" .. vim.env.NVIMR_ID)
    else
        fcntt = vim.fn.readfile(config.localtmpdir .. "/liblist_" .. vim.env.NVIMR_ID)
    end

    local obcur
    if vim.api.nvim_win_is_valid(ob_winnr) then
        obcur = vim.api.nvim_win_get_cursor(ob_winnr)
    end

    vim.api.nvim_set_option_value("modifiable", true, { buf = ob_buf })
    vim.api.nvim_buf_set_lines(ob_buf, 0, -1, false, fcntt)

    if vim.api.nvim_win_is_valid(ob_winnr) and obcur[1] <= #fcntt then
        vim.api.nvim_win_set_cursor(ob_winnr, obcur)
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = ob_buf })
    upobcnt = false
end

M.on_double_click = function()
    if vim.fn.line(".") == 2 then return end

    -- Toggle view: Objects in the workspace X List of libraries
    if vim.fn.line(".") == 1 then
        if curview == "libraries" then
            curview = "GlobalEnv"
            job.stdin("Server", "31\n")
        else
            curview = "libraries"
            job.stdin("Server", "321\n")
        end
        return
    end

    -- Toggle state of list or data.frame: open X closed
    local key = M.get_name()
    local curline = vim.fn.getline(vim.fn.line("."))
    if curview == "GlobalEnv" then
        if vim.fn.match(curline, "&#.*\t") > -1 then
            send_to_nvimcom("L", key)
        elseif
            vim.fn.match(curline, "\\[#.*\t") > -1
            or vim.fn.match(curline, "\\$#.*\t") > -1
            or vim.fn.match(curline, "<#.*\t") > -1
            or vim.fn.match(curline, ":#.*\t") > -1
        then
            key = vim.fn.substitute(key, "`", "", "g")
            job.stdin("Server", "33G" .. key .. "\n")
        else
            require("r.send").cmd("str(" .. key .. ")")
        end
    else
        if vim.fn.match(curline, "(#.*\t") > -1 then
            key = vim.fn.substitute(key, "`", "", "g")
            require("r.doc").ask_R_doc(key, M.get_pkg_name(), false)
        else
            if
                vim.fn.match(key, ":$")
                or vim.fn.match(curline, "\\[#.*\t") > -1
                or vim.fn.match(curline, "\\$#.*\t") > -1
                or vim.fn.match(curline, "<#.*\t") > -1
                or vim.fn.match(curline, ":#.*\t") > -1
            then
                job.stdin("Server", "33L" .. key .. "\n")
            else
                require("r.send").cmd("str(" .. key .. ")")
            end
        end
    end
end

M.on_right_click = function()
    if vim.fn.line(".") == 1 then return end

    local key = M.get_name()
    if key == "" then return end

    local line = vim.fn.getline(vim.fn.line("."))
    if vim.fn.match(line, "^   ##") > -1 then return end

    local isfunction = 0
    if vim.fn.match(line, "(#.*\t") > -1 then isfunction = 1 end

    if hasbrowsermenu then vim.fn.aunmenu("]RBrowser") end

    key = vim.fn.substitute(key, "\\.", "\\\\.", "g")
    key = vim.fn.substitute(key, " ", "\\ ", "g")

    vim.fn.execute("amenu ]RBrowser.summary(" .. key .. ') :call RAction("summary")<CR>')
    vim.fn.execute("amenu ]RBrowser.str(" .. key .. ') :call RAction("str")<CR>')
    vim.fn.execute("amenu ]RBrowser.names(" .. key .. ') :call RAction("names")<CR>')
    vim.fn.execute("amenu ]RBrowser.plot(" .. key .. ') :call RAction("plot")<CR>')
    vim.fn.execute("amenu ]RBrowser.print(" .. key .. ') :call RAction("print")<CR>')
    vim.fn.execute("amenu ]RBrowser.-sep01- <nul>")
    vim.fn.execute("amenu ]RBrowser.example(" .. key .. ') :call RAction("example")<CR>')
    vim.fn.execute("amenu ]RBrowser.help(" .. key .. ') :call RAction("help")<CR>')
    if isfunction then
        vim.fn.execute("amenu ]RBrowser.args(" .. key .. ') :call RAction("args")<CR>')
    end
    vim.fn.popup_menu("]RBrowser")
    hasbrowsermenu = true
end

M.on_BufUnload = function() send_to_nvimcom("N", "OnOBBufUnload") end

M.print_list_tree = function()
    -- FIXME: document this function as a debugging tool or delete it and the
    -- correspoding nvimrserver function.
    job.stdin("Server", "37\n")
end

return M
