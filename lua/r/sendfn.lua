local M = {}

local config = require('r.config')
local cursor = require('r.cursor_nav')

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

M.SendAboveLinesToR = function()
  local lines = vim.fn.getline(1, vim.fn.line('.') - 1)
  vim.fn.RSourceLines(lines, '')
end

M.SendFileToR = function(e)
  local bufnr = 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.fn.RSourceLines(lines, e)
end

-- Send the current paragraph to R. If m == 'down', move the cursor to the
-- first line of the next paragraph.
M.SendParagraphToR = function(e, m)
  local start_line, end_line = cursor.get_current_paragraph()

  local lines = vim.fn.getline(start_line, end_line)
  vim.fn.RSourceLines(lines, e, 'paragraph')

  if m == 'down' then
    cursor.move_cursor_next_paragraph()
  end
end

return M
