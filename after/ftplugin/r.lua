-- Override indentexpr to fix trailing-pipe/ggplot2 + indentation.
-- vim.schedule defers until after nvim-treesitter's FileType autocmd runs,
-- so our setting wins the race.
vim.schedule(function()
    if vim.bo.filetype == "r" then
        vim.bo.indentexpr = "v:lua.require'r.indent'.get_indent(v:lnum)"
    end
end)

