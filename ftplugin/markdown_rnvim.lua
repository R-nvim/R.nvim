if
    vim.g.R_filetypes
    and type(vim.g.R_filetypes) == "table"
    and vim.tbl_contains(vim.g.R_filetypes, "markdown")
then
    require("r.config").real_setup()
    require("r.rmd").setup()
end
