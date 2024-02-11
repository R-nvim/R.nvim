if
    vim.fn.exists("g:R_filetypes") == 1
    and type(vim.g.R_filetypes) == "table"
    and vim.fn.index(vim.g.R_filetypes, "rnoweb") == -1
then
    return
end

require("r.config").real_setup()

local config = require("r.config").get_config()

if config.rnowebchunk then
    -- Write code chunk in rnoweb files
    vim.api.nvim_buf_set_keymap(
        0,
        "i",
        "<",
        "<Esc>:lua require('r.rnw').write_chunk()<CR>a",
        { silent = true }
    )
end

-- Pointers to function whose purpose is the same in rnoweb, rmd,
-- rhelp and rdoc.
vim.b.IsInRCode = require("r.rnw").is_in_R_code

vim.api.nvim_buf_set_var(0, "rplugin_knitr_pattern", "^<<.*>>=$")

-- Key bindings
require("r.maps").create("rnoweb")

vim.schedule(function()
    require("r.pdf").setup()
    require("r.rnw").set_pdf_dir()
end)

vim.schedule(function()
    if vim.b.undo_ftplugin then
        vim.b.undo_ftplugin = vim.b.undo_ftplugin .. " | unlet! b:IsInRCode"
    else
        vim.b.undo_ftplugin = "unlet! b:IsInRCode"
    end
end)
