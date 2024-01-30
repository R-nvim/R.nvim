local M = {}

local config = require('r.config')
local cursor = require('r.cursor')
local paragraph = require('r.paragraph')

M.not_ready = function (_)
    require("r").warn("R is not ready yet.")
end

M.cmd = function (_)
    require("r").warn("Did you start R?")
end

M.GetSourceArgs = function(e)
  -- local sargs = config.get_config().source_args or ''
  local sargs = ''
  if config.get_config().source_args ~= '' then
    sargs = ', ' .. config.get_config().source_args
  end

  if e == 'echo' then
    sargs = sargs .. ', echo=TRUE'
  end
  return sargs
end

M.above_lines = function()
  local lines = vim.fn.getline(1, vim.fn.line('.') - 1)
  vim.fn.RSourceLines(lines, '')
end

M.source_file = function(e)
  local bufnr = 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.fn.RSourceLines(lines, e)
end

-- Send the current paragraph to R. If m == 'down', move the cursor to the
-- first line of the next paragraph.
M.paragraph = function(e, m)
  local start_line, end_line = paragraph.get_current()

  local lines = vim.fn.getline(start_line, end_line)
  vim.fn.RSourceLines(lines, e, 'paragraph')

  if m == 'down' then
    cursor.move_next_paragraph()
  end
end

M.line = function (m)
    M.cmd(vim.fn.getline(vim.fn.line(".")))
    if m == "down" then
        cursor.move_next_line()
    end
end

return M
