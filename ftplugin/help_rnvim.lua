if vim.api.nvim_buf_get_name(0):find("R.nvim/doc/R.nvim.txt") then
    local set_m = vim.api.nvim_buf_set_extmark
    local bn = vim.api.nvim_get_current_buf()
    local ns = vim.api.nvim_create_namespace("RnvimHelp")
    local lnum = vim.fn.search("^   Boolean  ") - 1
    vim.api.nvim_buf_clear_namespace(0, ns, lnum, lnum + 14)
    set_m(bn, ns, lnum, 3, { end_col = 10, hl_group = "Boolean" })
    set_m(bn, ns, lnum + 1, 3, { end_col = 10, hl_group = "Comment" })
    set_m(bn, ns, lnum + 2, 3, { end_col = 11, hl_group = "ErrorMsg" })
    set_m(bn, ns, lnum + 3, 3, { end_col = 11, hl_group = "Function" })
    set_m(bn, ns, lnum + 4, 3, { end_col = 10, hl_group = "Include" })
    set_m(bn, ns, lnum + 5, 3, { end_col = 9, hl_group = "Normal" })
    set_m(bn, ns, lnum + 6, 3, { end_col = 9, hl_group = "Number" })
    set_m(bn, ns, lnum + 7, 3, { end_col = 11, hl_group = "PreProc" })
    set_m(bn, ns, lnum + 8, 3, { end_col = 11, hl_group = "Special" })
    set_m(bn, ns, lnum + 9, 3, { end_col = 12, hl_group = "Statement" })
    set_m(bn, ns, lnum + 10, 3, { end_col = 15, hl_group = "StorageClass" })
    set_m(bn, ns, lnum + 11, 3, { end_col = 9, hl_group = "String" })
    set_m(bn, ns, lnum + 12, 3, { end_col = 12, hl_group = "Structure" })
    set_m(bn, ns, lnum + 13, 3, { end_col = 7, hl_group = "Type" })
    set_m(bn, ns, lnum + 14, 3, { end_col = 10, hl_group = "Typedef" })
end
