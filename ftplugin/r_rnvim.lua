if
  vim.fn.exists('g:R_filetypes') == 1
  and type(vim.g.R_filetypes) == 'table'
  and vim.fn.index(vim.g.R_filetypes, 'r') == -1
then
  return
end

local routfile

-- Override default values with user variable options and set internal variables.
require('r.config').real_setup()

local get_R_output = function (_)
    local config = require("r.config").get_config()
    if vim.fn.filereadable(routfile) then
        if config.routnotab then
            vim.api.nvim_command("split " .. routfile)
            vim.api.nvim_command("set filetype=rout")
            vim.api.nvim_command("normal! %<c-w>%<c-p>")
        else
            vim.api.nvim_command("tabnew " .. routfile)
            vim.api.nvim_command("set filetype=rout")
            vim.api.nvim_command("normal! gT")
        end
    else
      vim.api.nvim_command('tabnew ' .. routfile)
      vim.api.nvim_command('set filetype=rout')
      vim.api.nvim_command('normal! gT')
    end
  else
    require('r').warn(
      "The file '" .. routfile .. "' either does not exist or is not readable."
    )
  end
end

-- Run R CMD BATCH on the current file and load the resulting .Rout in a split window
require('r').show_R_out = function()
  routfile = vim.fn.expand('%:r') .. '.Rout'
  if vim.fn.bufloaded(routfile) == 1 then
    vim.api.nvim_command('bunload ' .. routfile)
    vim.fn.delete(routfile)
  end

  -- If not silent, the user will have to type <Enter>
  vim.api.nvim_command('silent update')

  local config = require('r.config').get_config()
  local rcmd
  if vim.fn.has('win32') == 1 then
    rcmd = config.R_cmd
      .. ' CMD BATCH --no-restore --no-save "'
      .. vim.fn.expand('%')
      .. '" "'
      .. routfile
      .. '"'
  else
    rcmd = {
      config.R_cmd,
      'CMD',
      'BATCH',
      '--no-restore',
      '--no-save',
      vim.fn.expand('%'),
      routfile,
    }
  end
  require('r.job').start('R_CMD', rcmd, { on_exit = get_R_output })
end

local is_in_R_code = function(_)
  return 1
end

-- Default IsInRCode function when the plugin is used as a global plugin
vim.b.IsInRCode = is_in_R_code

-- Key bindings
require("r.maps").create("r")

-- Only .R files are sent to R

if vim.b.undo_ftplugin then
  vim.b.undo_ftplugin = vim.b.undo_ftplugin .. ' | unlet! b:IsInRCode'
else
  vim.b.undo_ftplugin = 'unlet! b:IsInRCode'
end
