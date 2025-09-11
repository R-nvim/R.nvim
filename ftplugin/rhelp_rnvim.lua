if
    vim.g.R_filetypes
    and type(vim.g.R_filetypes) == "table"
    and not vim.tbl_contains(vim.g.R_filetypes, "rhelp")
then
    return
end

-- Override default values with user variable options and set internal variables.
require("r.config").real_setup()

-- Key bindings and menu items
require("r.maps").create("rhelp")
