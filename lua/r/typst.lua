local M = {}

M.make = function(outform)
    vim.cmd("update")
    local send = require("r.send").cmd
    if outform == "pdf" then
        if vim.api.nvim_buf_get_name(0):lower():find("%.[Rr][Tt][Yy][Pp]$") then
            send('knitr::knit2pdf("' .. vim.api.nvim_buf_get_name(0) .. '")')
        else
            send([[system("typst compile ']] .. vim.api.nvim_buf_get_name(0) .. [['")]])
        end
    else
        send('knitr::knit("' .. vim.api.nvim_buf_get_name(0) .. '")')
    end
end

return M
