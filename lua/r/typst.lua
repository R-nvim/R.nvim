local M = {}

M.make = function(outform)
    local send = require("r.send").cmd
    if outform == "pdf" then
        send('knitr::knit2pdf("' .. vim.api.nvim_buf_get_name(0) .. '")')
    else
        send('knitr::knit("' .. vim.api.nvim_buf_get_name(0) .. '")')
    end
end

return M
