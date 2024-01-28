local cfg = require("r.config").get_config()

local check_installed = function()
    if vim.fn.executable(cfg.pdfviewer) == 0 then
        vim.notify("R-Nvim: Please, set the value of `pdfviewer`. The application `" .. cfg.pdfviewer .. "` was not found.", vim.log.levels.WARN)
    end
end

local M = {}

M.setup = function()
    check_installed()
    if cfg.pdfviewer == "zathura" then
        M.open = require("r.pdf.zathura").open
        M.SyncTeX_forward = require("r.pdf.zathura").SyncTeX_forward
    elseif cfg.pdfviewer == "evince" then
        M.open = require("r.pdf.evince").open
        M.SyncTeX_forward = require("r.pdf.evince").SyncTeX_forward
    elseif cfg.pdfviewer == "okular" then
        M.open = require("r.pdf.okular").open
        M.SyncTeX_forward = require("r.pdf.okular").SyncTeX_forward
    elseif vim.fn.has("win32") == 1 and cfg.pdfviewer == "sumatra" then
        M.open = require("r.pdf.sumatra").open
        M.SyncTeX_forward = require("r.pdf.sumatra").SyncTeX_forward
    elseif vim.g.rplugin.is_darwin and cfg.pdfviewer == "skim" then
        M.open = require("r.pdf.skim").open
        M.SyncTeX_forward = require("r.pdf.skim").SyncTeX_forward
    elseif cfg.pdfviewer == "qpdfview" then
        M.open = require("r.pdf.qpdfview").open
        M.SyncTeX_forward = require("r.pdf.qpdfview").SyncTeX_forward
    else
        M.open = require("r.pdf.generic").open
        M.SyncTeX_forward = require("r.pdf.generic").SyncTeX_forward
    end

    vim.g.rplugin.has_wmctrl = 0
    vim.g.rplugin.has_awbt = 0

    if vim.fn.has("win32") == 0 and not vim.g.rplugin.is_darwin and os.getenv("WAYLAND_DISPLAY") == "" then
        if vim.fn.executable("wmctrl") > 0 then
            vim.g.rplugin.has_wmctrl = 1
        else
            if vim.o.filetype == "rnoweb" and cfg.synctex then
                vim.notify("The application wmctrl must be installed to edit Rnoweb effectively.", vim.log.levels.WARN)
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
    --             vim.g.rplugin.has_awbt = 1
    --         end
    --     end
    -- end
end

function RRaiseWindow(wttl)
    if vim.g.rplugin.has_wmctrl then
        vim.fn.system("wmctrl -a '" .. wttl .. "'")
        if vim.v.shell_error == 0 then
            return 1
        else
            return 0
        end
    elseif os.getenv("WAYLAND_DISPLAY") ~= "" then
        if os.getenv("GNOME_SHELL_SESSION_MODE") ~= "" and vim.g.rplugin.has_awbt then
            local sout = vim.fn.system("busctl --user call org.gnome.Shell " ..
                        "/de/lucaswerkmeister/ActivateWindowByTitle " ..
                        "de.lucaswerkmeister.ActivateWindowByTitle " ..
                        "activateBySubstring s '" .. wttl .. "'")
            if vim.v.shell_error == 0 then
                if sout:find('false') then
                    return 0
                else
                    return 1
                end
            else
                vim.fn.RWarningMsg('Error running Gnome Shell Extension "Activate Window By Title": ' ..
                            vim.fn.substitute(sout, "\n", " ", "g"))
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
                vim.fn.RWarningMsg('Error running swaymsg: ' .. vim.fn.substitute(sout, "\n", " ", "g"))
                return 0
            end
        end
    end
    return 0
end


-- FIXME: is this necessary?
-- if vim.bo.filetype == 'rnoweb' then
--     RSetPDFViewer()
--     SetPDFdir()
--     if cfg.synctex and vim.fn.getenv("DISPLAY") ~= "" and cfg.pdfviewer == "evince" then
--         vim.g.rplugin.evince_loop = 0
--         Run_EvinceBackward()
--     end
-- end

return M
