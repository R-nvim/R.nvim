local M = {}

--- Quick setup: simply store user options
---@param opts table
M.setup = function(opts)
  -- print('hello')
  -- vim.notify('sdfsdf')

  require('r.config').store_user_opts(opts)

  vim.api.nvim_set_keymap(
    'n',
    '<leader>h',
    ':lua require"r".SendAboveLinesToR()<CR>',
    { noremap = true, silent = true }
  )
end

return M
