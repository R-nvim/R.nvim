if
    vim.g.R_filetypes
    and type(vim.g.R_filetypes) == "table"
    and not vim.tbl_contains(vim.g.R_filetypes, "rmd")
then
    return
end

require("r.config").real_setup()
require("r.rmd").setup()
