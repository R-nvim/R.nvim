if vim.fn.exists("g:R_filetypes") == 1 and type(vim.g.R_filetypes) == "table" and vim.fn.index(vim.g.R_filetypes, 'rnoweb') == -1 then
    return
end

require("r.config").real_setup()

local config = require("r.config").get_config()

if config.rnowebchunk then
    -- Write code chunk in rnoweb files
    vim.api.nvim_buf_set_keymap(0, 'i', "<", "<Esc>:lua require('r.rnw').write_chunk()<CR>a", {silent = true})
end

-- Pointers to functions whose purposes are the same in rnoweb, rrst, rmd,
-- rhelp and rdoc and which are called at common_global.vim
-- FIXME: replace with references to Lua functions when they are written.
vim.b.IsInRCode = require("r.rnw").is_in_R_code

vim.api.nvim_buf_set_var(0, "rplugin_knitr_pattern", "^<<.*>>=$")

-- Key bindings
local m = require("r.maps")
m.start()
m.edit()
m.send()
m.control()

m.create('nvi', 'RSetwd',        'rd', ':call RSetWD()')

-- Only .Rnw files use these functions:
m.create('nvi', 'RSweave',      'sw', ':lua require("r.rnw").weave("nobib", false, false)')
m.create('nvi', 'RMakePDF',     'sp', ':lua require("r.rnw").weave("nobib", false, true)')
m.create('nvi', 'RBibTeX',      'sb', ':lua require("r.rnw").weave("bibtex", false, true)')
if config.rm_knit_cache then
    m.create('nvi', 'RKnitRmCache', 'kr', ':lua require("r.rnw").rm_knit_cache()')
end
m.create('nvi', 'RKnit',        'kn', ':lua require("r.rnw").weave("nobib", true, false)')
m.create('nvi', 'RMakePDFK',    'kp', ':lua require("r.rnw").weave("nobib", true, true)')
m.create('nvi', 'RBibTeXK',     'kb', ':lua require("r.rnw").weave("bibtex", true, true)')
m.create('ni',  'RSendChunk',   'cc', ':lua require("r.rnw").send_chunk("silent", "stay")')
m.create('ni',  'RESendChunk',  'ce', ':lua require("r.rnw").send_chunk("echo", "stay")')
m.create('ni',  'RDSendChunk',  'cd', ':lua require("r.rnw").send_chunk("silent", "down")')
m.create('ni',  'REDSendChunk', 'ca', ':lua require("r.rnw").send_chunk("echo", "down")')
m.create('nvi', 'ROpenPDF',     'op', ':call ROpenPDF("Get Master")')
if config.synctex then
    m.create('ni', 'RSyncFor',  'gp', ':lua require("r.rnw").SyncTeX_forward(false)')
    m.create('ni', 'RGoToTeX',  'gt', ':lua require("r.rnw").SyncTeX_forward(true)')
end
m.create('n', 'RNextRChunk',     'gn', ':lua require("r.rnw").next_chunk()')
m.create('n', 'RPreviousRChunk', 'gN', ':lua require("r.rnw").previous_chunk()')

vim.schedule(function ()
    require("r.pdf").setup()
    require("r.rnw").set_pdf_dir()
end)

-- FIXME: not working:
if vim.fn.exists("b:undo_ftplugin") == 1 then
    vim.api.nvim_buf_set_var(0, "undo_ftplugin", vim.b.undo_ftplugin .. " | unlet! b:IsInRCode")
else
    vim.api.nvim_buf_set_var(0, "undo_ftplugin", "unlet! b:IsInRCode")
end
