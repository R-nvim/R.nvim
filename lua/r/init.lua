local M = {}

--- Call vim.notify() with a warning message
---@param msg string
M.warn = function(msg)
    vim.schedule(
        function() vim.notify(msg, vim.log.levels.WARN, { title = "R.nvim" }) end
    )
end

--- Call vim.notify() with to inform a message
---@param msg string
M.inform = function(msg)
    vim.schedule(
        function() vim.notify(msg, vim.log.levels.INFO, { title = "R.nvim" }) end
    )
end

--- Quick setup: simply store user options
---@param opts table | nil
M.setup = function(opts)
    if opts then require("r.config").store_user_opts(opts) end
end

return M
