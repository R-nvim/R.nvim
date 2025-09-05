if
    vim.g.R_filetypes
    and type(vim.g.R_filetypes) == "table"
    and not vim.tbl_contains(vim.g.R_filetypes, "rnoweb")
then
    return
end

require("r.config").real_setup()

-- Key bindings
require("r.maps").create("rnoweb")

vim.schedule(function()
    require("r.pdf").setup()
    require("r.rnw").set_pdf_dir()
end)
