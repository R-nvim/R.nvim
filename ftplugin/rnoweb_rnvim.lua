if
    vim.g.R_filetypes
    and type(vim.g.R_filetypes) == "table"
    and vim.fn.index(vim.g.R_filetypes, "rnoweb") == -1
then
    return
end

require("r.config").real_setup()

local config = require("r.config").get_config()

if config.rnw_chunk_keymap ~= "" then
    -- Write code chunk in rnoweb files
    vim.api.nvim_buf_set_keymap(
        0,
        "i",
        config.rnw_chunk_keymap,
        "<Cmd>:lua require('r.rnw').write_chunk()<CR>",
        { silent = true }
    )
end

-- Key bindings
require("r.maps").create("rnoweb")

vim.schedule(function()
    require("r.pdf").setup()
    require("r.rnw").set_pdf_dir()
end)
