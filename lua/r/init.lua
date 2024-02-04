local M = {}

M.warn = function(msg) vim.notify(msg, vim.log.levels.WARN, { title = "R-Nvim" }) end

--- Quick setup: simply store user options
---@param opts table | nil
M.setup = function(opts)
    if opts then require("r.config").store_user_opts(opts) end
end

return M
