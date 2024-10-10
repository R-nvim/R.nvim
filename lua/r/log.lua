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
        function()
            vim.notify(
                msg,
                vim.log.levels.INFO,
                { title = "R.nvim", hide_from_history = true }
            )
        end
    )
end

return M
