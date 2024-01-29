local cfg = require("r.config").get_config()

local M = {}

M.cmd = function(what)
    -- FIXME: SendCmdToR not working. Replace with Lua functions when available.
    if what == "render" then
        vim.cmd("update")
        vim.g.SendCmdToR('quarto::quarto_render("' .. vim.fn.substitute(vim.fn.expand('%'), '\\', '/', 'g') .. '"' .. cfg.quarto_render_args .. ')')
    elseif what == "preview" then
        vim.cmd("update")
        vim.g.SendCmdToR('quarto::quarto_preview("' .. vim.fn.substitute(vim.fn.expand('%'), '\\', '/', 'g') .. '"' .. cfg.quarto_preview_args .. ')')
    else
        vim.g.SendCmdToR('quarto::quarto_preview_stop()')
    end
end

return M
