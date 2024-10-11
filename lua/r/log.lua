--- Helper function to call vim.notify() with scheduled execution
---@param msg string
---@param level number
---@param opts table
local function notify(msg, level, opts)
    vim.schedule(function() vim.notify(msg, level, opts) end)
end

local M = {}

--- Call vim.notify() with a warning message
---@param msg string
M.warn = function(msg) notify(msg, vim.log.levels.WARN, { title = "R.nvim" }) end

--- Call vim.notify() to inform a message
---@param msg string
M.inform = function(msg)
    notify(msg, vim.log.levels.INFO, { title = "R.nvim", hide_from_history = true })
end

return M
