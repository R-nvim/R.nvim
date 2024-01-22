if vim.fn.exists("g:R_filetypes") and type(vim.g.R_filetypes) == "table" and vim.fn.index(vim.g.R_filetypes, 'r') == -1 then
    return
end

local routfile

-- Override default values with user variable options and set internal variables.
require("r.config").real_setup()

-- Check if b:pdf_is_open already exists to avoid errors at other places
if not vim.fn.exists("b:pdf_is_open") then
    vim.b.pdf_is_open = 0
end

function GetRCmdBatchOutput(...)
    if vim.fn.filereadable(routfile) then
        if vim.g.R_routnotab == 1 then
            vim.api.nvim_command("split " .. routfile)
            vim.api.nvim_command("set filetype=rout")
            vim.api.nvim_command("normal! %<c-w>%<c-p>")
        else
            vim.api.nvim_command("tabnew " .. routfile)
            vim.api.nvim_command("set filetype=rout")
            vim.api.nvim_command("normal! gT")
        end
    else
        vim.notify("The file '" .. routfile .. "' either does not exist or is not readable.")
    end
end

-- Run R CMD BATCH on the current file and load the resulting .Rout in a split window
function ShowRout()
    routfile = vim.fn.expand("%:r") .. ".Rout"
    if vim.fn.bufloaded(routfile) then
        vim.api.nvim_command("bunload " .. routfile)
        vim.fn.delete(routfile)
    end

    -- If not silent, the user will have to type <Enter>
    vim.api.nvim_command("silent update")

    local rcmd
    if vim.fn.has("win32") then
        rcmd = vim.g.rplugin.Rcmd .. ' CMD BATCH --no-restore --no-save "' .. vim.fn.expand("%") .. '" "' .. routfile .. '"'
    else
        rcmd = { vim.g.rplugin.Rcmd, "CMD", "BATCH", "--no-restore", "--no-save", vim.fn.expand("%"),  routfile }
    end
    vim.g.rplugin.jobs["R_CMD"] = vim.fn.jobstart(rcmd, { on_exit = GetRCmdBatchOutput })
end

-- Default IsInRCode function when the plugin is used as a global plugin
function DefaultIsInRCode(_)
    return 1
end

vim.b.IsInRCode = DefaultIsInRCode

-- Key bindings and menu items
vim.fn.RCreateStartMaps()
vim.fn.RCreateEditMaps()

-- Only .R files are sent to R
vim.fn.RCreateMaps('ni', 'RSendFile',  'aa', ':call SendFileToR("silent")')
vim.fn.RCreateMaps('ni', 'RESendFile', 'ae', ':call SendFileToR("echo")')
vim.fn.RCreateMaps('ni', 'RShowRout',  'ao', ':call ShowRout()')

vim.fn.RCreateSendMaps()
vim.fn.RControlMaps()
vim.fn.RCreateMaps('nvi', 'RSetwd',    'rd', ':call RSetWD()')

vim.fn.RSourceOtherScripts()

if vim.b.undo_ftplugin then
    vim.b.undo_ftplugin = vim.b.undo_ftplugin .. " | unlet! b:IsInRCode"
else
    vim.b.undo_ftplugin = "unlet! b:IsInRCode"
end
