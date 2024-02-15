local config = require("r.config").get_config()
local warn = require("r").warn
local job = require("r.job")

local check_installed = function()
    if vim.fn.executable(config.pdfviewer) == 0 then
        warn(
            "R.nvim: Please, set the value of `pdfviewer`. The application `"
                .. config.pdfviewer
                .. "` was not found."
        )
    end
end

local M = {}

M.setup = function()
    local ptime = vim.fn.reltime()
    check_installed()
    if config.pdfviewer == "zathura" then
        M.open2 = require("r.pdf.zathura").open
        M.SyncTeX_forward = require("r.pdf.zathura").SyncTeX_forward
    elseif config.pdfviewer == "evince" then
        M.open2 = require("r.pdf.evince").open
        M.SyncTeX_forward = require("r.pdf.evince").SyncTeX_forward
    elseif config.pdfviewer == "okular" then
        M.open2 = require("r.pdf.okular").open
        M.SyncTeX_forward = require("r.pdf.okular").SyncTeX_forward
    elseif config.is_windows and config.pdfviewer == "sumatra" then
        M.open2 = require("r.pdf.sumatra").open
        M.SyncTeX_forward = require("r.pdf.sumatra").SyncTeX_forward
    elseif config.is_darwin and config.pdfviewer == "skim" then
        M.open2 = require("r.pdf.skim").open
        M.SyncTeX_forward = require("r.pdf.skim").SyncTeX_forward
    elseif config.pdfviewer == "qpdfview" then
        M.open2 = require("r.pdf.qpdfview").open
        M.SyncTeX_forward = require("r.pdf.qpdfview").SyncTeX_forward
    else
        M.open2 = require("r.pdf.generic").open
        M.SyncTeX_forward = require("r.pdf.generic").SyncTeX_forward
    end

    config.has_wmctrl = false

    if not config.is_windows and not config.is_darwin and not vim.env.WAYLAND_DISPLAY then
        if vim.fn.executable("wmctrl") > 0 then
            config.has_wmctrl = true
            -- FIXME: Use wmctrl to find title and pid of current window
            -- config.term_title = ?
            -- config.term_pid = ?
        else
            if vim.o.filetype == "rnoweb" and config.synctex then
                warn(
                    "The application wmctrl must be installed to edit Rnoweb effectively."
                )
            end
        end
    elseif
        vim.env.XDG_CURRENT_DESKTOP == "sway" or vim.env.XDG_SESSION_DESKTOP == "sway"
    then
        local sout = vim.fn.system("swaymsg -t get_tree")
        local t = vim.json.decode(sout, { luanil = { object = true, array = true } })
        for _, v1 in pairs(t.nodes) do
            if #v1 and v1.type == "output" and v1.nodes then
                for _, v2 in pairs(v1.nodes) do
                    if #v2 and v2.type == "workspace" and v2.nodes then
                        for _, v3 in pairs(v2.nodes) do
                            if v3.focused == true then
                                config.term_title = v3.name
                                config.term_pid = v3.pid
                            end
                        end
                    end
                end
            end
        end
        -- FIXME: find title and pid of current window on other systesm
        -- (Windows, OSX, Gnome, KDE, etc).
    end

    require("r.edit").add_to_debug_info(
        "pdf setup",
        vim.fn.reltimefloat(vim.fn.reltime(ptime, vim.fn.reltime())),
        "Time"
    )
end

--- Call the appropriate function to open a PDF document.
---@param fullpath string The path to the PDF file.
M.open = function(fullpath)
    if config.open_pdf == 0 then return end

    if fullpath == "Get Master" then
        local fpath = require("r.rnw").SyncTeX_get_master() .. ".pdf"
        fpath = vim.b.rplugin_pdfdir .. "/" .. fpath:gsub(".*/", "")
        M.open(fpath)
        return
    end

    local fname = fullpath:gsub(".*/", "")
    if job.is_running(fullpath) then
        if config.open_pdf == 2 then M.focus_window(fname, job.get_pid(fullpath)) end
        return
    end

    M.open2(fullpath)
end

--- Request the windows manager to focus a window.
--- Currently, has support only for Xorg.
---@param wttl string Part of the window title.
---@param pid number Pid of window application.
M.focus_window = function(wttl, pid)
    if config.has_wmctrl then
        vim.fn.system("wmctrl -a '" .. wttl .. "'")
    elseif
        vim.env.XDG_CURRENT_DESKTOP == "sway" or vim.env.XDG_SESSION_DESKTOP == "sway"
    then
        if pid and pid ~= 0 then
            vim.fn.system("swaymsg '[pid=\"" .. tostring(pid) .. "\"] focus'")
        else
            vim.fn.system("swaymsg '[pid=\"" .. wttl .. "\"] focus'")
        end
    end
end

return M
