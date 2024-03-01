local config = require("r.config").get_config()
local warn = require("r").warn
local job = require("r.job")
local send_to_nvimcom = require("r.run").send_to_nvimcom

local lc_env = string.lower(
    tostring(vim.env.LC_MESSAGES) .. tostring(vim.env.LC_ALL) .. tostring(vim.env.LANG)
)
local isutf8 = (lc_env:find("utf-8", 1, true) or lc_env:find("utf8", 1, true)) and true
    or false
local curview = "GlobalEnv"
local ob_win
local ob_buf
local upobcnt = false
local running_objbr = false
local auto_starting = true

-- Popup menu
local hasbrowsermenu = false

--- Escape with backticks invalid R names
---@param word string
---@param esc_reserved boolean
---@return string
local add_backticks = function(word, esc_reserved)
    -- Unamed list element
    if word:find("^%[%[") then return word end

    local punct = {
        "!",
        "'",
        '"',
        "#",
        "%%",
        "&",
        "%(",
        "%)",
        "%*",
        "%+",
        ",",
        "-",
        "/",
        "\\",
        ":",
        ";",
        "<",
        "=",
        ">",
        "?",
        "@",
        "%[",
        "/",
        "%]",
        "%^",
        "%$",
        "%{",
        "|",
        "%}",
        "~",
    }

    local reserved = {
        "if",
        "else",
        "repeat",
        "while",
        "function",
        "for",
        "in",
        "next",
        "break",
        "TRUE",
        "FALSE",
        "NULL",
        "Inf",
        "NaN",
        "NA",
        "NA_integer_",
        "NA_real_",
        "NA_complex_",
        "NA_character",
    }

    local need_bt = false

    if word:find(" ") or word:find("^[0-9_]") then
        need_bt = true
    else
        local esc_list = punct
        if esc_reserved then
            for _, v in pairs(reserved) do
                table.insert(esc_list, "^" .. v .. "$")
            end
        end
        for _, v in pairs(esc_list) do
            if word:find(v) then
                need_bt = true
                break
            end
        end
    end
    if need_bt then word = "`" .. word .. "`" end
    return word
end

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
    vim.api.nvim_set_option_value("signcolumn", "no", { scope = "local" })
    vim.api.nvim_set_option_value("foldcolumn", "0", { scope = "local" })

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
    -- vim.api.nvim_buf_set_keymap(
    --     0,
    --     "n",
    --     "<RightMouse>",
    --     "<Cmd>lua require('r.browser').on_right_click()<CR>",
    --     opts
    -- )

    vim.api.nvim_create_autocmd("BufEnter", {
        command = "stopinsert",
        pattern = "<buffer>",
    })

    vim.api.nvim_create_autocmd("BufUnload", {
        command = "lua require('r.browser').on_BufUnload()",
        pattern = "<buffer>",
    })

    vim.api.nvim_buf_set_lines(0, 0, 1, false, { ".GlobalEnv | Libraries" })

    require("r.config").real_setup()
    require("r.maps").create("rbrowser")
end

local find_parent

--- Return the parent list, data.frame or S4 object
---@param child string
---@param curline number
---@param curpos number
---@return string
find_parent = function(child, curline, curpos)
    local line
    local idx
    local parent
    local suffix
    while curline > 3 do
        curline = curline - 1
        line = vim.api.nvim_buf_get_lines(0, curline - 1, curline, true)[1]
        line = line:gsub("\t.*", "")
        idx = line:find("#")
        if idx < curpos then
            parent = line:sub(idx + 1)
            if line:find("%[#") or line:find("%$#") then
                suffix = "$"
                break
            elseif line:find("<#") then
                suffix = "@"
                break
            else
                local msg = "Unrecognized type of parent: `"
                    .. parent
                    .. "`\nKnown types are `data.frame`s, `list`s and `S4` objects."
                vim.notify(msg, vim.log.levels.ERROR, { title = "R.nvim" })
                return ""
            end
        end
    end

    if not parent then
        local msg = "Failed to find parent."
        vim.notify(msg, vim.log.levels.ERROR, { title = "R.nvim" })
        return ""
    end

    parent = add_backticks(parent, false)

    local fullname = parent .. suffix .. child

    local spacelimit
    if curview == "GlobalEnv" then
        spacelimit = 6
    else
        spacelimit = isutf8 and 12 or 8
    end
    if idx > spacelimit then return find_parent(fullname, curline, idx) end
    return fullname
end

-- Start Object Browser
local start_OB
start_OB = function()
    -- Either open or close the Object Browser
    local savesb = vim.o.switchbuf
    vim.o.switchbuf = "useopen,usetab"

    if ob_buf and vim.api.nvim_buf_is_loaded(ob_buf) then
        local ob_tab = vim.api.nvim_win_get_tabpage(ob_win)
        vim.api.nvim_buf_delete(ob_buf, {})
        if ob_tab ~= vim.api.nvim_win_get_tabpage(0) then start_OB() end
    else
        local edbuf = vim.api.nvim_get_current_buf()

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
                vim.cmd.sb(require("r.edit").get_rscript_buf())
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
        ob_buf = vim.api.nvim_get_current_buf()
        ob_win = vim.api.nvim_get_current_win()

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

    job.stdin("Server", "31\n")
    send_to_nvimcom("A", "RObjBrowser")

    start_OB()
    running_objbr = false

    if config.hook.after_ob_open then config.hook.after_ob_open() end
end

--- Return the active pane of the Object Browser
---@return string
M.get_curview = function() return curview end

--- Get the name of parent library
---@return string
M.get_pkg_name = function()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    while lnum > 2 do
        local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
        if line:find("^   :#[0-9a-zA-Z%.]*\t") then
            return tostring(line:gsub("   :#(.-)\t.*", "%1"))
        end
        lnum = lnum - 1
    end
    return ""
end

--- Get name of object on te current line
---@param lnum number
---@param line string
---@return string
M.get_name = function(lnum, line)
    if lnum < 3 or line:find("^$") then return "" end

    local idx = line:find("#")
    local word = line:sub(idx + 1):gsub("\009.*", "")

    word = add_backticks(word, true)

    if idx == 5 then
        -- top level object
        if curview == "libraries" then
            return word .. ":"
        else
            return word
        end
    else
        if curview == "libraries" then
            if isutf8 then
                if idx == 12 then
                    word = word:gsub("%$%[%[", "[[")
                    return word
                end
            elseif idx == 8 then
                word = word:gsub("%$%[%[", "[[")
                return word
            end
        end
        if idx > 5 then
            -- Find the parent data.frame or list
            word = find_parent(word, lnum, idx - 1)
            word = word:gsub("%$%[%[", "[[")
            return word
        else
            -- Wrong object name delimiter: should never happen.
            local msg = "(idx = " .. tostring(idx) .. ") " .. word
            vim.notify(msg, vim.log.levels.ERROR, { title = "R.nvim" })
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

    if not ob_buf then
        upobcnt = false
        return "Object_Browser not listed"
    end

    local lines
    if wht == "GlobalEnv" then
        lines = vim.fn.readfile(config.localtmpdir .. "/globenv_" .. vim.env.RNVIM_ID)
    else
        lines = vim.fn.readfile(config.localtmpdir .. "/liblist_" .. vim.env.RNVIM_ID)
    end
    if not lines then lines = { "Error loading data" } end

    vim.api.nvim_set_option_value("modifiable", true, { buf = ob_buf })
    vim.api.nvim_buf_set_lines(ob_buf, 0, -1, false, lines)

    vim.api.nvim_set_option_value("modifiable", false, { buf = ob_buf })
    upobcnt = false
end

M.on_double_click = function()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    if lnum == 2 then return end

    -- Toggle view: Objects in the workspace X List of libraries
    if lnum == 1 then
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
    lnum = vim.api.nvim_win_get_cursor(0)[1]
    local curline = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
    local key = M.get_name(lnum, curline)
    if curview == "GlobalEnv" then
        if curline:find("&#.*\t") then
            send_to_nvimcom("L", key)
        elseif
            curline:find("%[#.*\t")
            or curline:find("%$#.*\t")
            or curline:find("<#.*\t")
            or curline:find(":#.*\t")
        then
            key = key:gsub("`", "")
            job.stdin("Server", "33G" .. key .. "\n")
        else
            require("r.send").cmd("str(" .. key .. ")")
        end
    else
        if curline:find("%(#.*\t") or curline:find(";#.*\t") then
            key = key:gsub("`", "")
            require("r.doc").ask_R_doc(key, M.get_pkg_name(), false)
        else
            if
                string.find(key, ":%$")
                or curline:find("%[#.*\t")
                or curline:find("%$#.*\t")
                or curline:find("<#.*\t")
                or curline:find(":#.*\t")
            then
                job.stdin("Server", "33L" .. key .. "\n")
            else
                require("r.send").cmd("str(" .. key .. ")")
            end
        end
    end
end

M.on_right_click = function()
    -- The function vim.fn.popup_menu() doesn't work when called from Lua.
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    if lnum == 1 then return end

    local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
    local key = M.get_name(lnum, line)
    if key == "" then return end

    if line:find("^   ##") then return end

    local isfunction = false
    if line:find("%(#") then isfunction = true end

    if hasbrowsermenu then vim.fn.aunmenu("]RBrowser") end

    key = key:gsub("%.", "\\.")
    key = key:gsub(" ", "\\ ")

    vim.fn.execute(
        "amenu ]RBrowser.summary("
            .. key
            .. ") <Cmd>lua require('r.run').action('summary')<CR>"
    )
    vim.fn.execute(
        "amenu ]RBrowser.str(" .. key .. ") <Cmd>lua require('r.run').action('str')<CR>"
    )
    vim.fn.execute(
        "amenu ]RBrowser.names("
            .. key
            .. ") <Cmd>lua require('r.run').action('nvim.names')<CR>"
    )
    vim.fn.execute(
        "amenu ]RBrowser.plot(" .. key .. ") <Cmd>lua require('r.run').action('plot')<CR>"
    )
    vim.fn.execute(
        "amenu ]RBrowser.print("
            .. key
            .. ") <Cmd>lua require('r.run').action('args')<CR>"
    )
    vim.fn.execute("amenu ]RBrowser.-sep01- <nul>")
    vim.fn.execute(
        "amenu ]RBrowser.example("
            .. key
            .. ") <Cmd>lua require('r.run').action('example')<CR>"
    )
    vim.fn.execute(
        "amenu ]RBrowser.help(" .. key .. ") <Cmd>lua require('r.run').action('help')<CR>"
    )
    if isfunction then
        vim.fn.execute(
            "amenu ]RBrowser.args("
                .. key
                .. ") <Cmd>lua require('r.run').action('args')<CR>"
        )
    end
    vim.fn.popup_menu("]RBrowser")
    hasbrowsermenu = true
end

M.on_BufUnload = function()
    ob_buf = nil
    ob_win = nil
    send_to_nvimcom("N", "OnOBBufUnload")
end

--- Return Object Browser buffer number
---@return number
M.get_buf_nr = function() return ob_buf end

return M
