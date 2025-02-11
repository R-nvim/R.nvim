--[[
This module implements the Object Browser functionality for the R.nvim Neovim plugin.
It provides an interactive interface within Neovim to browse and inspect R objects,
such as variables, data frames, lists, and libraries, directly from the editor.

Key components:

- `start_OB`: Opens or closes the Object Browser window in Neovim.
- `M.start`: Initiates the Object Browser if R is running.
- `M.on_double_click`: Handles double-click events within the Object Browser to
  toggle views or inspect objects.
- `M.get_name`, `M.get_pkg_name`: Utility functions to retrieve object names and
  package names from the current cursor position.
- `add_backticks`: Escapes invalid R object names by wrapping them in backticks.
- Custom key mappings: Allows users to bind arbitrary commands or Lua functions
  to keys within the Object Browser.

This file integrates with `r.config`, `r.job`, `r.run`, and `r.send` to communicate
with the R backend and update the Object Browser interface accordingly.
]]

local config = require("r.config").get_config()
local warn = require("r.log").warn
local job = require("r.job")
local hooks = require("r.hooks")
local send_to_nvimcom = require("r.run").send_to_nvimcom

-- Determine if the locale uses UTF-8 encoding
local lc_env = string.lower(
    tostring(vim.env.LC_MESSAGES) .. tostring(vim.env.LC_ALL) .. tostring(vim.env.LANG)
)
local isutf8 = (lc_env:find("utf-8", 1, true) or lc_env:find("utf8", 1, true)) and true
    or false

local state = {
    curview = "GlobalEnv", -- Current view in the Object Browser
    win = nil, -- Object Browser window reference, previously `ob_win`
    buf = nil, -- Object Browser buffer reference, previously `ob_buf`
    upobcnt = false, -- Prevents multiple simultaneous updates
    is_running = false, -- Indicates if the Object Browser is currently running, previously `running_objbr`
    auto_starting = true, -- Controls automatic starting behavior
    hasbrowsermenu = false, -- Popup menu state
}

--- Escape invalid R names with backticks
---@param word string
---@param esc_reserved boolean
---@return string
local function add_backticks(word, esc_reserved)
    -- Unnamed list element (e.g., [[1]])
    if word:find("^%[%[") then return word end

    -- Punctuation characters that are invalid in R names
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

    -- Reserved words in R
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

    local invalid_r_name = false -- If true, needs backticks.

    if word:find(" ") or word:find("^[0-9_]") then
        invalid_r_name = true
    else
        local esc_list = {}
        vim.list_extend(esc_list, punct)
        if esc_reserved then
            for _, v in ipairs(reserved) do
                table.insert(esc_list, "^" .. v .. "$")
            end
        end
        for _, v in ipairs(esc_list) do
            if word:find(v) then
                invalid_r_name = true
                break
            end
        end
    end
    if invalid_r_name then word = "`" .. word .. "`" end
    return word
end

--- Set buffer options for the Object Browser window
local function set_buf_options()
    local options = {
        wrap = false,
        list = false,
        number = false,
        relativenumber = false,
        cursorline = false,
        cursorcolumn = false,
        spell = false,
        winfixwidth = false,
        swapfile = false,
        bufhidden = "wipe",
        buftype = "nofile",
        syntax = "rbrowser",
        iskeyword = "@,48-57,_,.",
        signcolumn = "no",
        foldcolumn = "0",
    }

    for opt, val in pairs(options) do
        vim.api.nvim_set_option_value(opt, val, { scope = "local" })
    end

    local opts = { silent = true, noremap = true, expr = false, buffer = true }
    vim.keymap.set("n", "<CR>", require("r.browser").on_double_click, opts)
    vim.keymap.set("n", "<2-LeftMouse>", require("r.browser").on_double_click, opts)
    -- Uncomment if needed
    -- vim.keymap.set("n", "<RightMouse>", require("r.browser").on_right_click, opts)

    -- Set up custom key mappings from config.objbr_mappings
    for key, action in pairs(config.objbr_mappings) do
        if type(action) == "string" then
            -- Mapping is an R code string
            vim.keymap.set(
                "n",
                key,
                function() require("r.browser").run_custom_command(action) end,
                opts
            )
        elseif type(action) == "function" then
            -- Mapping is a Lua function
            vim.keymap.set("n", key, function() action() end, opts)
        else
            warn("Invalid mapping for key '" .. key .. "'. Must be a string or function.")
        end
    end

    -- Stop insert mode when entering the buffer
    vim.api.nvim_create_autocmd("BufEnter", {
        command = "stopinsert",
        pattern = "<buffer>",
    })

    vim.api.nvim_create_autocmd("BufUnload", {
        command = "lua require('r.browser').on_BufUnload()",
        pattern = "<buffer>",
    })

    vim.api.nvim_buf_set_lines(0, 0, 1, false, { ".GlobalEnv | Libraries" })
    require("r.maps").create("rbrowser")
end

--- Return the parent list, data.frame or S4 object
---@param child string
---@param curline number
---@param curpos number
---@return string
local function find_parent(child, curline, curpos)
    local line, idx, parent, suffix
    while curline > 3 do
        curline = curline - 1
        line = vim.api.nvim_buf_get_lines(0, curline - 1, curline, true)[1]
        line = line:gsub("\t.*", "")
        idx = line:find("#")
        if idx == nil then return "" end
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
                    .. "`\nKnown types are `data.frame`s, `list`s, and `S4` objects."
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

    local spacelimit = (state.curview == "GlobalEnv") and 6 or (isutf8 and 12 or 8)
    if idx > spacelimit then return find_parent(fullname, curline, idx) end
    return fullname
end

--- Start or toggle the Object Browser window
local function start_OB()
    local savesb = vim.o.switchbuf
    vim.o.switchbuf = "useopen,usetab"

    if state.buf and vim.api.nvim_buf_is_loaded(state.buf) then
        -- Object Browser is open; close it
        local ob_tab = nil
        if vim.api.nvim_win_is_valid(state.win) then
            ob_tab = vim.api.nvim_win_get_tabpage(state.win)
        end
        vim.api.nvim_buf_delete(state.buf, {})
        if ob_tab ~= vim.api.nvim_win_get_tabpage(0) then start_OB() end
    else
        -- Open Object Browser
        local edbuf = vim.api.nvim_get_current_buf()

        -- Determine placement of the Object Browser based on configuration
        if config.objbr_place:find("RIGHT") then
            vim.cmd("botright vsplit Object_Browser")
        elseif config.objbr_place:find("LEFT") then
            vim.cmd("topleft vsplit Object_Browser")
        elseif config.objbr_place:find("TOP") then
            vim.cmd("topleft split Object_Browser")
        elseif config.objbr_place:find("BOTTOM") then
            vim.cmd("botright split Object_Browser")
        else
            -- Place next to the console or script buffer
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

        -- Adjust size based on configuration
        if config.objbr_place:find("left") or config.objbr_place:find("right") then
            vim.cmd("vertical resize " .. config.objbr_w)
        else
            vim.cmd("resize " .. config.objbr_h)
        end

        set_buf_options()
        state.curview = "GlobalEnv"
        state.buf = vim.api.nvim_get_current_buf()
        state.win = vim.api.nvim_get_current_win()

        if config.objbr_auto_start and state.auto_starting then
            state.auto_starting = false
            vim.cmd.sb(edbuf)
        end
    end

    -- Restore original 'switchbuf' option
    vim.cmd("set switchbuf=" .. savesb)
end

local M = {}

--- Open an Object Browser window
function M.start(_)
    -- Only opens the Object Browser if R is running
    if vim.g.R_Nvim_status < 5 then
        warn("The Object Browser can be opened only if R is running.")
        return
    end

    if state.is_running then
        -- Prevents calling the function twice due to BufEnter event
        return
    end

    state.is_running = true

    -- Request data from R to populate the Object Browser
    job.stdin("Server", "31\n")
    send_to_nvimcom("A", "RObjBrowser")

    start_OB()
    state.is_running = false

    hooks.run(config, "after_ob_open", true)
end

--- Return the active pane of the Object Browser
---@return string
function M.get_curview() return state.curview end

--- Toggle between "GlobalEnv" and "libraries" views
function M.toggle_view()
    if state.curview == "libraries" then
        state.curview = "GlobalEnv"
        job.stdin("Server", "31\n")
    else
        state.curview = "libraries"
        job.stdin("Server", "321\n")
    end
end

--- Get the name of parent library
---@return string
function M.get_pkg_name()
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

--- Get name of object on the current line in the Object Browser
---@param lnum number
---@param line string
---@return string
function M.get_name(lnum, line)
    if lnum < 3 or line:find("^$") then return "" end

    local idx = line:find("#")
    local word = line:sub(idx + 1):gsub("\009.*", "")

    word = add_backticks(word, true)

    if idx == 5 then
        -- Top-level object
        if state.curview == "libraries" then
            return word .. ":"
        else
            return word
        end
    else
        if state.curview == "libraries" then
            if (isutf8 and idx == 12) or (idx == 8) then
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

--- Expand or collapse lists and data frames in the Object Browser
---@param stt string
function M.open_close_lists(stt) job.stdin("Server", "34" .. stt .. state.curview .. "\n") end

--- Update the Object Browser content
---@param what string
function M.update_OB(what)
    local wht = (what == "both") and state.curview or what
    if state.curview ~= wht then return "curview != what" end
    if state.upobcnt then
        -- vim.api.nvim_err_writeln("OB called twice")
        return "OB called twice"
    end

    state.upobcnt = true

    if not state.buf then
        state.upobcnt = false
        return "Object_Browser not listed"
    end

    -- Read the data from temporary files created by R
    local lines
    if wht == "GlobalEnv" then
        lines = vim.fn.readfile(config.localtmpdir .. "/globenv_" .. vim.env.RNVIM_ID)
    else
        lines = vim.fn.readfile(config.localtmpdir .. "/liblist_" .. vim.env.RNVIM_ID)
    end
    if not lines then lines = { "Error loading data" } end

    -- Update the Object Browser buffer
    vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)

    vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
    state.upobcnt = false
end

function M.on_double_click()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    if lnum == 2 then return end

    -- Toggle between "GlobalEnv" and "libraries" views
    if lnum == 1 then
        M.toggle_view()
        return
    end

    -- Get the current line and object name
    lnum = vim.api.nvim_win_get_cursor(0)[1]
    local curline = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
    local key = M.get_name(lnum, curline)
    if state.curview == "GlobalEnv" then
        if curline:find("&#.*\t") then
            -- Object is a list or data.frame
            send_to_nvimcom("L", key)
        elseif
            curline:find("%[#.*\t")
            or curline:find("%$#.*\t")
            or curline:find("<#.*\t")
            or curline:find(":#.*\t")
        then
            -- Expand or collapse the object
            key = key:gsub("`", "")
            job.stdin("Server", "33G" .. key .. "\n")
        else
            -- Run str() on the object
            require("r.send").cmd("str(" .. key .. ")")
        end
    else
        if curline:find("%(#.*\t") or curline:find(";#.*\t") then
            -- Function or special object; show documentation
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
                -- Expand or collapse the object in libraries view
                job.stdin("Server", "33L" .. key .. "\n")
            else
                require("r.send").cmd("str(" .. key .. ")")
            end
        end
    end
end

function M.on_right_click()
    -- The function vim.fn.popup_menu() doesn't work when called from Lua.
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    if lnum == 1 then return end

    local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
    local key = M.get_name(lnum, line)
    if key == "" then return end

    if line:find("^   ##") then return end

    local isfunction = false
    if line:find("%(#") then isfunction = true end

    if state.hasbrowsermenu then vim.fn.aunmenu("]RBrowser") end

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
    state.hasbrowsermenu = true
end

function M.on_BufUnload()
    state.buf = nil
    state.win = nil
    send_to_nvimcom("N", "OnOBBufUnload")
end

--- Return Object Browser buffer number
---@return number
function M.get_buf_nr() return state.buf end

--- Run a custom command on the selected object
---@param command string
function M.run_custom_command(command)
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    if lnum < 3 then return end

    local curline = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
    local object_name = M.get_name(lnum, curline)
    if object_name == "" then
        warn("No object selected.")
        return
    end

    local placeholder = config.objbr_placeholder or "{object}"

    -- Replace placeholder with the object name
    local cmd_to_run = command:gsub(placeholder, object_name)

    -- If no placeholder was found, append the object name to the command
    if cmd_to_run == command then cmd_to_run = command .. "(" .. object_name .. ")" end

    -- Execute the command on the selected object
    require("r.send").cmd(cmd_to_run)
end

return M
