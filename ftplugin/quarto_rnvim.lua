if vim.fn.exists("g:R_filetypes") == 1 and type(vim.g.R_filetypes) == "table" and vim.fn.index(vim.g.R_filetypes, 'quarto') == -1 then
    return
end


require("r.config").real_setup()
require("r.rmd").setup()

local m = require("r.maps")
m.create('n', 'RQuartoRender',  'qr', ':lua require("r.quarto").command("render")')
m.create('n', 'RQuartoPreview', 'qp', ':lua require("r.quarto").command("preview")')
m.create('n', 'RQuartoStop',    'qs', ':lua require("r.quarto").command("stop")')
