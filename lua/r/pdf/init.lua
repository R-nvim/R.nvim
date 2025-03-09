local config = require("r.config").get_config()
local utils = require("r.utils")
local warn = require("r.log").warn
local job = require("r.job")
local uv = vim.uv

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
    local ptime = uv.hrtime()

    if config.pdfviewer ~= "" then check_installed() end

    if config.pdfviewer == "zathura" then
        M.open2 = require("r.pdf.zathura").open
        M.SyncTeX_forward = require("r.pdf.zathura").SyncTeX_forward
    elseif config.is_windows and config.pdfviewer == "sumatra" then
        M.open2 = require("r.pdf.sumatra").open
        M.SyncTeX_forward = require("r.pdf.sumatra").SyncTeX_forward
    elseif config.is_darwin and config.pdfviewer == "skim" then
        M.open2 = require("r.pdf.skim").open
        M.SyncTeX_forward = require("r.pdf.skim").SyncTeX_forward
    else
        M.open2 = require("r.pdf.generic").open
        M.SyncTeX_forward = require("r.pdf.generic").SyncTeX_forward
    end

    if vim.o.filetype == "rnoweb" and config.synctex then
        if
            not config.is_windows
            and not config.is_darwin
            and not vim.env.WAYLAND_DISPLAY
            and vim.env.DISPLAY
        then
            if vim.fn.executable("xprop") == 1 and vim.fn.executable("wmctrl") == 1 then
                config.has_X_tools = true
            else
                warn(
                    "SyncTeX requires the applications `xprop` and `wmctrl` for search forward and backward."
                )
            end
        end
    end

    require("r.utils").get_focused_win_info()

    ptime = (uv.hrtime() - ptime) / 1000000000
    require("r.edit").add_to_debug_info("pdf setup (async)", ptime, "Time")
end

--- Call the appropriate function to open a PDF document.
---@param fullpath string The path to the PDF file.
M.open = function(fullpath)
    if config.open_pdf == "no" then return end

    if fullpath == "Get Master" then
        local fpath = require("r.rnw").SyncTeX_get_master() .. ".pdf"
        fpath = vim.b.rplugin_pdfdir .. "/" .. fpath:gsub(".*/", "")
        M.open(fpath)
        return
    end

    local fname = fullpath:gsub(".*/", "")
    if job.is_running(fullpath) then
        if config.open_pdf:find("focus") then
            utils.focus_window(fname, job.get_pid(fullpath))
        end
        return
    end

    M.open2(fullpath)
end

return M
