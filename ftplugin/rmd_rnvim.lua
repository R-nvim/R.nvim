if vim.fn.exists("g:R_filetypes") == 1 and type(vim.g.R_filetypes) == "table" and vim.fn.index(vim.g.R_filetypes, 'rmd') == -1 then
    return
end

require("r.config").real_setup()

local cfg = require("r.config").get_config()

if type(cfg.rmdchunk) == "number" and (cfg.rmdchunk == 1 or cfg.rmdchunk == 2) then
    vim.api.nvim_buf_set_keymap(0, 'i', "`", "<Esc>:call RWriteRmdChunk()<CR>a", {silent = true})
elseif type(cfg.rmdchunk) == "string" then
    vim.api.nvim_buf_set_keymap(0, 'i', cfg.rmdchunk, "<Esc>:call RWriteRmdChunk()<CR>a", {silent = true})
end


-- Pointers to functions whose purposes are the same in rnoweb, rrst, rmd,
-- rhelp and rdoc:
vim.api.nvim_buf_set_var(0, "IsInRCode", require("r.rmd").is_in_R_code)
vim.api.nvim_buf_set_var(0, "PreviousRChunk", require("r.rmd").previous_chunk)
vim.api.nvim_buf_set_var(0, "NextRChunk", require("r.rmd").next_chunk)
vim.api.nvim_buf_set_var(0, "SendChunkToR", require("r.rmd").send_R_chunk)

vim.api.nvim_buf_set_var(0, "rplugin_knitr_pattern", "^``` *{.*}$")

-- Key bindings
local m = require("r.maps")
m.start()
m.edit()
m.send()
m.control()

m.create('nvi', 'RSetwd',        'rd', ':call RSetWD()')

-- Only .Rmd and .qmd files use these functions:
m.create('nvi', 'RKnit',           'kn', ':call RKnit()')
m.create('ni',  'RSendChunk',      'cc', ':call b:SendChunkToR("silent", "stay")')
m.create('ni',  'RESendChunk',     'ce', ':call b:SendChunkToR("echo", "stay")')
m.create('ni',  'RDSendChunk',     'cd', ':call b:SendChunkToR("silent", "down")')
m.create('ni',  'REDSendChunk',    'ca', ':call b:SendChunkToR("echo", "down")')
m.create('n',   'RNextRChunk',     'gn', ':call b:NextRChunk()')
m.create('n',   'RPreviousRChunk', 'gN', ':call b:PreviousRChunk()')

vim.schedule(function ()
    require("r.pdf").setup()
end)

-- FIXME: not working:
if vim.fn.exists("b:undo_ftplugin") == 1 then
    vim.api.nvim_buf_set_var(0, "undo_ftplugin", vim.b.undo_ftplugin .. " | unlet! b:IsInRCode b:PreviousRChunk b:NextRChunk b:SendChunkToR")
else
    vim.api.nvim_buf_set_var(0, "undo_ftplugin", "unlet! b:IsInRCode b:PreviousRChunk b:NextRChunk b:SendChunkToR")
end
