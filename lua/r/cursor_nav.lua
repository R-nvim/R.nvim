local M = {}

-- Returns the line number of the first non-empty line after the current
-- paragraph. If the cursor is on the last paragraph, returns the last line
-- number.
M.find_next_paragraph = function()
  local current_line = vim.fn.line('.')
  local next_empty_line = current_line

  -- Search for the next empty line (paragraph separator)
  while next_empty_line <= vim.fn.line('$') do
    if vim.fn.trim(vim.fn.getline(next_empty_line)) == '' then
      break
    end
    next_empty_line = next_empty_line + 1
  end

  -- Move cursor to the first non-empty line after the empty line
  while next_empty_line <= vim.fn.line('$') do
    if vim.fn.trim(vim.fn.getline(next_empty_line)) ~= '' then
      return next_empty_line
    end
    next_empty_line = next_empty_line + 1
  end

  return vim.fn.line('$')
end

-- Moves the cursor to the first non-empty line after the current paragraph.
M.move_cursor_next_paragraph = function()
  vim.api.nvim_win_set_cursor(0, { M.find_next_paragraph(), 0 })
end

-- Get the starting and ending line numbers of the current paragraph.
-- Returns a table with two keys: 'start' and 'end'.
-- The 'start' key contains the line number of the first line of the paragraph.
-- The 'end' key contains the line number of the last line of the paragraph.
-- If the cursor is on the last paragraph, the 'end' key contains the last line
-- number.

M.get_current_paragraph = function()
  local current_line = vim.fn.line('.')
  local start_line = current_line
  local end_line = current_line

  -- Find the start of the paragraph
  while start_line > 1 and vim.fn.trim(vim.fn.getline(start_line - 1)) ~= '' do
    start_line = start_line - 1
  end

  -- Find the end of the paragraph
  local last_line = vim.fn.line('$')
  while
    end_line < last_line and vim.fn.trim(vim.fn.getline(end_line + 1)) ~= ''
  do
    end_line = end_line + 1
  end

  return start_line, end_line
end

return M
