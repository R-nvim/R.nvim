local M = {}

M.command = function(what)
    local config = require("r.config").get_config()
    local send_cmd = require("r.send").cmd
    if what == "stop" then
        send_cmd("quarto::quarto_preview_stop()")
        return
    end

    vim.cmd("update")
    local qa = what == "render" and config.quarto_render_args
        or config.quarto_preview_args
    local cmd = "quarto::quarto_"
        .. what
        .. '("'
        .. vim.fn.expand("%"):gsub("\\", "/")
        .. '"'
        .. qa
        .. ")"
    send_cmd(cmd)
end

return M
