if
    vim.fn.exists("g:R_filetypes") == 1
    and type(vim.g.R_filetypes) == "table"
    and vim.fn.index(vim.g.R_filetypes, "rhelp") == -1
then
    return
end

-- Override default values with user variable options and set internal variables.
require("r.config").real_setup()

-- Key bindings and menu items
require("r.maps").create("rhelp")

vim.schedule(function()
    if vim.b.undo_ftplugin then
        vim.b.undo_ftplugin = vim.b.undo_ftplugin .. " | unlet! b:IsInRCode"
    else
        vim.b.undo_ftplugin = "unlet! b:IsInRCode"
    end
end)
