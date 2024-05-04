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
