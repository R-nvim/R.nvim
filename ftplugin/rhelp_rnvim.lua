if
    vim.g.R_filetypes
    and type(vim.g.R_filetypes) == "table"
    and vim.fn.index(vim.g.R_filetypes, "rhelp") == -1
then
    return
end

-- Override default values with user variable options and set internal variables.
require("r.config").real_setup()

-- Key bindings and menu items
require("r.maps").create("rhelp")
