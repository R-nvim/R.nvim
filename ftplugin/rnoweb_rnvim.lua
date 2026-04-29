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

local config = require("r.config").get_config()

if config.quarto_chunk_hl.highlight then require("r.quarto").setup_chunk_hl() end
if config.quarto_chunk_hl.yaml_hl then require("r.quarto").yaml_hl() end

vim.schedule(function()
    require("r.pdf").setup()
    require("r.rnw").set_pdf_dir()
end)
