local M = {}

function M.find()
    -- return vim.fn.glob("*.Rproj")
    return vim.fn.findfile("./;")
end

return M
