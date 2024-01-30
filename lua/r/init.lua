local M = {}

M.warn = function (msg)
    vim.notify(msg, vim.log.levels.WARN, {title = 'R-Nvim'})
end

--- Quick setup: simply store user options
---@param opts table
M.setup = function(opts)
  require('r.config').store_user_opts(opts)
end

return M
