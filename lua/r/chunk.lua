local M = {}

local is_inside_chunk = function(language)
  -- This will create a pattern like ```{r or ```{python
  language = '```{' .. language
  local pos = vim.fn.searchpair(language, '', '```', 'nbW')

  if pos == 0 then
    return false
  end

  return true
end

M.is_inside_r = function()
  return is_inside_chunk('r')
end

M.is_inside_python = function()
  return is_inside_chunk('python')
end

return M
