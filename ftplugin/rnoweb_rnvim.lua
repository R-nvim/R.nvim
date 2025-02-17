if
    vim.g.R_filetypes
    and type(vim.g.R_filetypes) == "table"
    and vim.fn.index(vim.g.R_filetypes, "rnoweb") == -1
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
