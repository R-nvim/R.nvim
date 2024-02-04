local config = require("r.config").get_config()
local warn = require("r").warn

local check_installed = function()
    if vim.fn.executable(config.pdfviewer) == 0 then
        warn(
            "R-Nvim: Please, set the value of `pdfviewer`. The application `"
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
    elseif vim.fn.has("win32") == 1 and config.pdfviewer == "sumatra" then
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

    config.has_wmctrl = 0
    config.has_awbt = 0

    if
        vim.fn.has("win32") == 0
        and not config.is_darwin
        and os.getenv("WAYLAND_DISPLAY") == ""
    then
        if vim.fn.executable("wmctrl") > 0 then
            config.has_wmctrl = 1
        else
            if vim.o.filetype == "rnoweb" and config.synctex then
                warn(
                    "The application wmctrl must be installed to edit Rnoweb effectively."
                )
            end
        end
    end

    -- FIXME: The ActivateWindowByTitle extension is no longer working
    -- if os.getenv("WAYLAND_DISPLAY") ~= "" and os.getenv("GNOME_SHELL_SESSION_MODE") ~= "" then
    --     if vim.fn.executable('busctl') > 0 then
    --         local sout = vim.fn.system('busctl --user call org.gnome.Shell.Extensions ' ..
    --                 '/org/gnome/Shell/Extensions org.gnome.Shell.Extensions ' ..
    --                 'GetExtensionInfo "s" "activate-window-by-title@lucaswerkmeister.de"')
    --         if sout:find('Activate Window') then
    --             config.has_awbt = 1
    --         end
    --     end
    -- end
    require("r.edit").add_to_debug_info(
        "pdf setup",
        vim.fn.reltimefloat(vim.fn.reltime(ptime, vim.fn.reltime())),
        "Time"
    )
end

M.open = function(fullpath)
    if config.openpdf == 0 then return end

    if fullpath == "Get Master" then
        local fpath = vim.fn.SyncTeX_GetMaster() .. ".pdf"
        fpath = vim.b.rplugin_pdfdir .. "/" .. fpath:gsub(".*/", "")
        M.open(fpath)
        return
    end

    if not vim.b.pdf_is_open then
        if config.openpdf == 1 then vim.b.pdf_is_open = true end
        M.open2(fullpath)
    end
end

function RRaiseWindow(wttl)
    if config.has_wmctrl then
        vim.fn.system("wmctrl -a '" .. wttl .. "'")
        if vim.v.shell_error == 0 then
            return 1
        else
            return 0
        end
    elseif os.getenv("WAYLAND_DISPLAY") ~= "" then
        if os.getenv("GNOME_SHELL_SESSION_MODE") ~= "" and config.has_awbt then
            local sout = vim.fn.system(
                "busctl --user call org.gnome.Shell "
                    .. "/de/lucaswerkmeister/ActivateWindowByTitle "
                    .. "de.lucaswerkmeister.ActivateWindowByTitle "
                    .. "activateBySubstring s '"
                    .. wttl
                    .. "'"
            )
            if vim.v.shell_error == 0 then
                if sout:find("false") then
                    return 0
                else
                    return 1
                end
            else
                warn(
                    'Error running Gnome Shell Extension "Activate Window By Title": '
                        .. vim.fn.substitute(sout, "\n", " ", "g")
                )
                return 0
            end
        elseif os.getenv("XDG_CURRENT_DESKTOP") == "sway" then
            local sout = vim.fn.system("swaymsg -t get_tree")
            if vim.v.shell_error == 0 then
                if sout:find(wttl) then
                    -- Should move to the workspace where Zathura is and then try to focus the window?
                    -- vim.fn.system('swaymsg for_window [title="' .. wttl .. '"] focus')
                    return 1
                else
                    return 0
                end
            else
                warn("Error running swaymsg: " .. vim.fn.substitute(sout, "\n", " ", "g"))
                return 0
            end
        end
    end
    return 0
end

return M
