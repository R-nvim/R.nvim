local M = {}

M.command = function(what)
    local config = require("r.config").get_config()
    local send_cmd = require("r.send").cmd
    if what == "render" then
        vim.cmd("update")
        send_cmd(
            'quarto::quarto_render("'
                .. vim.fn.expand("%"):gsub("\\", "/")
                .. '"'
                .. config.quarto_render_args
                .. ")"
        )
    elseif what == "preview" then
        vim.cmd("update")
        send_cmd(
            'quarto::quarto_preview("'
                .. vim.fn.expand("%"):gsub("\\", "/")
                .. '"'
                .. config.quarto_preview_args
                .. ")"
        )
    else
        send_cmd("quarto::quarto_preview_stop()")
    end
end

return M
