local config = require("r.config").get_config()
local send_to_nvimcom = require("r.run").send_to_nvimcom
local warn = require("r").warn
local utils = require("r.utils")
local cursor = require("r.cursor")
local job = require("r.job")
local doc_buf_id = nil

local M = {}

local get_win_width = function() return vim.o.columns > 80 and 80 or vim.o.columns - 1 end

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
    local rbn = require("r.term").get_buf_nr()
    if vim.fn.bufname("%") == "Object_Browser" or vim.fn.bufnr("%") == rbn then
        local savesb = vim.o.switchbuf
        vim.o.switchbuf = "useopen,usetab"
        vim.cmd.sb(require("r.edit").get_rscript_name())
        vim.cmd("set switchbuf=" .. savesb)
    else
        if getclass then firstobj = cursor.get_first_obj() end
    end

    local htw = get_win_width()
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

    local rbn = require("r.term").get_buf_nr()
    if vim.fn.bufnr("%") == rbn then
        -- Exit Terminal mode and go to Normal mode
        vim.cmd("stopinsert")
    end

    if vim.fn.bufname("%"):match("Object_Browser") or vim.fn.bufnr("%") == rbn then
        local savesb = vim.o.switchbuf
        vim.o.switchbuf = "useopen,usetab"
        vim.cmd.sb(require("r.edit").get_rscript_name())
        vim.cmd("set switchbuf=" .. savesb)
    end

    if doc_buf_id and vim.api.nvim_buf_is_loaded(doc_buf_id) then
        local savesb = vim.o.switchbuf
        vim.o.switchbuf = "useopen,usetab"
        vim.cmd.sb(doc_buf_id)
        vim.cmd("set switchbuf=" .. savesb)
    else
        if vpager == "tab" or vpager == "float" then
            vim.cmd("tabnew R_doc")
        else
            if vim.fn.winwidth(0) < 80 then
                vim.cmd("topleft split R_doc")
            else
                vim.cmd("split R_doc")
            end
            if vim.fn.winheight(0) < 20 then vim.cmd("resize 20") end
        end
    end

    doc_buf_id = vim.api.nvim_win_get_buf(0)
    vim.api.nvim_buf_set_name(doc_buf_id, rkeyword)

    vim.api.nvim_set_option_value("modifiable", true, { scope = "local" })
    vim.api.nvim_buf_set_lines(0, 0, -1, true, {})

    txt = txt:gsub("\019", "'")
    local lines
    if txt:find("\008") then
        lines = require("r.rdoc").fix_rdoc(txt)
    else
        lines = vim.split(txt, "\020")
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, true, lines)
    if rkeyword:match("R History") then
        vim.api.nvim_set_option_value("filetype", "r", { scope = "local" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
    elseif rkeyword:match("(help)") or vim.fn.search("\008", "nw") > 0 then
        require("r.rdoc").set_buf_options()
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
    elseif rkeyword:find("%.Rd$") then
        -- Called by devtools::load_all().
        -- See https://github.com/jalvesaq/Nvim-R/issues/482
        vim.api.nvim_set_option_value("filetype", "rhelp", { scope = "local" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
    else
        vim.o.syntax = "rout"
        vim.api.nvim_set_option_value("bufhidden", "wipe", { scope = "local" })
        vim.api.nvim_set_option_value("number", false, { scope = "local" })
        vim.api.nvim_set_option_value("swapfile", false, { scope = "local" })
        vim.api.nvim_set_option_value("buftype", "nofile", { scope = "local" })
        vim.api.nvim_buf_set_keymap(
            0,
            "n",
            "q",
            ":q<CR>",
            { noremap = true, silent = true }
        )
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
    end
    vim.cmd("setlocal nomodified")
    vim.cmd("stopinsert")
end

--- Function called by nvimcom when the user requests R documentation on a
--- object under cursor and there are two or more libraries that might be the
--- package where the object is.
---@param topic string The object name, usually a function name.
---@param libs table Names of libraries.
M.choose_lib = function(topic, libs)
    local htw = get_win_width()
    vim.schedule(function()
        vim.ui.select(libs, {
            prompt = "Please, select one library:",
        }, function(choice, _)
            if choice then
                send_to_nvimcom(
                    "E",
                    'nvimcom:::nvim.help("'
                        .. topic
                        .. '", '
                        .. htw
                        .. 'L, package="'
                        .. choice
                        .. '")'
                )
            end
        end)
    end)
end

--- Load HTML document
---@param fullpath string
---@param browser string
M.load_html = function(fullpath, browser)
    if config.open_html == 0 then return end

    local fname = fullpath:gsub(".*/", "")
    if job.is_running(fullpath) then
        if config.open_html == 2 then utils.focus_window(fname, job.get_pid(fullpath)) end
        return
    end

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

    job.start(fullpath, cmd, { detach = true, on_exit = job.on_exit })
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
