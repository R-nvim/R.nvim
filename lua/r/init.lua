
local M = {}

--- Quick setup: simply store user options
---@param opts table
M.setup = function (opts)
    require('r.config').store_user_opts(opts)
end

return M
