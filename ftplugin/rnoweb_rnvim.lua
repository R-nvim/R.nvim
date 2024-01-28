if vim.fn.exists("g:R_filetypes") == 1 and type(vim.g.R_filetypes) == "table" and vim.fn.index(vim.g.R_filetypes, 'rnoweb') == -1 then
    return
end

require("r.config").real_setup()

local cfg = require("r.config").get_config()

if cfg.rnowebchunk then
    -- Write code chunk in rnoweb files
    vim.api.nvim_buf_set_keymap(0, 'i', "<", "<Esc>:call RWriteChunk()<CR>a", {silent = true})
end

vim.cmd("source " .. vim.fn.substitute(vim.g.rplugin.home, " ", "\\ ", "g") .. "/R/rnw_fun.vim")

-- Pointers to functions whose purposes are the same in rnoweb, rrst, rmd,
-- rhelp and rdoc and which are called at common_global.vim
-- FIXME: replace with references to Lua functions when they are written.
vim.cmd([[
let b:IsInRCode = function("RnwIsInRCode")
let b:PreviousRChunk = function("RnwPreviousChunk")
let b:NextRChunk = function("RnwNextChunk")
let b:SendChunkToR = function("RnwSendChunkToR")
]])

vim.api.nvim_buf_set_var(0, "rplugin_knitr_pattern", "^<<.*>>=$")

-- Key bindings
local m = require("r.maps")
m.start()
m.edit()
m.send()
m.control()

m.create('nvi', 'RSetwd',        'rd', ':call RSetWD()')

-- Only .Rnw files use these functions:
m.create('nvi', 'RSweave',      'sw', ':call RWeave("nobib", 0, 0)')
m.create('nvi', 'RMakePDF',     'sp', ':call RWeave("nobib", 0, 1)')
m.create('nvi', 'RBibTeX',      'sb', ':call RWeave("bibtex", 0, 1)')
if cfg.rm_knit_cache then
    m.create('nvi', 'RKnitRmCache', 'kr', ':call RKnitRmCache()')
end
m.create('nvi', 'RKnit',        'kn', ':call RWeave("nobib", 1, 0)')
m.create('nvi', 'RMakePDFK',    'kp', ':call RWeave("nobib", 1, 1)')
m.create('nvi', 'RBibTeXK',     'kb', ':call RWeave("bibtex", 1, 1)')
m.create('nvi', 'RIndent',      'si', ':call RnwToggleIndentSty()')
m.create('ni',  'RSendChunk',   'cc', ':call b:SendChunkToR("silent", "stay")')
m.create('ni',  'RESendChunk',  'ce', ':call b:SendChunkToR("echo", "stay")')
m.create('ni',  'RDSendChunk',  'cd', ':call b:SendChunkToR("silent", "down")')
m.create('ni',  'REDSendChunk', 'ca', ':call b:SendChunkToR("echo", "down")')
m.create('nvi', 'ROpenPDF',     'op', ':call ROpenPDF("Get Master")')
if cfg.synctex then
    m.create('ni', 'RSyncFor',  'gp', ':call SyncTeX_forward()')
    m.create('ni', 'RGoToTeX',  'gt', ':call SyncTeX_forward(1)')
end
m.create('n', 'RNextRChunk',     'gn', ':call b:NextRChunk()')
m.create('n', 'RPreviousRChunk', 'gN', ':call b:PreviousRChunk()')

vim.schedule(function ()
    require("r.pdf").setup()
    vim.fn.SetPDFdir()
end)

-- FIXME: not working:
if vim.fn.exists("b:undo_ftplugin") == 1 then
    vim.api.nvim_buf_set_var(0, "undo_ftplugin", vim.b.undo_ftplugin .. " | unlet! b:IsInRCode b:PreviousRChunk b:NextRChunk b:SendChunkToR")
else
    vim.api.nvim_buf_set_var(0, "undo_ftplugin", "unlet! b:IsInRCode b:PreviousRChunk b:NextRChunk b:SendChunkToR")
end
