vim.api.nvim_create_augroup("rft", { clear = true })
vim.api.nvim_create_autocmd("BufRead", {
    group = "rft",
    pattern = "*.Rhistory",
    callback = function() vim.api.nvim_set_option_value("syntax", "r", {}) end,
})
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    group = "rft",
    pattern = "*.Rout",
    callback = function() vim.api.nvim_set_option_value("syntax", "rout", {}) end,
})
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    group = "rft",
    pattern = "*.Rproj",
    callback = function() vim.api.nvim_set_option_value("syntax", "dcf", {}) end,
})
vim.filetype.add({ pattern = { [".*%.Rtyp$"] = { "typst", { priority = math.huge } } } })

-- This is needed because scripts.vim sees leading '#' and sets conf; override it
-- TODO: I am not sure if this is ok, but I do not find a better way at the moment
vim.api.nvim_create_autocmd("FileType", {
    group = "rft",
    pattern = "conf",
    callback = function(ev)
        if vim.api.nvim_buf_get_name(ev.buf):match("%.Rtyp$") then
            vim.bo[ev.buf].filetype = "typst"
        end
    end,
})
