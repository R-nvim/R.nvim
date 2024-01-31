local cfg = require("r.config").get_config()

M = {}

--- Create maps.
--- For each noremap we need a vnoremap including <Esc> before the :call,
--- otherwise nvim will call the function as many times as the number of selected
--- lines. If we put <Esc> in the noremap, nvim will bell.
---@param mode string Modes to which create maps (normal, visual and insert)
--- and whether the cursor have to go the beginning of the line
---@param plug string The "<Plug>" name.
---@param combo string Key combination.
---@param target string The command or function to be called.
M.create = function(mode, plug, combo, target)
    if cfg.disable_cmds.plug then
        return
    end
    local tg
    local il
    if mode:find('0') then
        tg = target .. '<CR>0'
        il = 'i'
    elseif mode:find('%.') then
        tg = target
        il = 'a'
    else
        tg = target .. '<CR>'
        il = 'a'
    end
    if mode:find("n") then
        vim.api.nvim_buf_set_keymap(0, 'n', '<Plug>' .. plug, tg, {silent = true, noremap = true, expr = false})
        if not cfg.user_maps_only and vim.fn.hasmapto('<Plug>' .. plug, "n") == 0 then
            vim.api.nvim_buf_set_keymap(0, 'n', '<LocalLeader>' .. combo, '<Plug>' .. plug, {silent = true, noremap = true, expr = false})
        end
    end
    if mode:find("v") then
        vim.api.nvim_buf_set_keymap(0, 'v', '<Plug>' .. plug, '<Esc>' .. tg, {silent = true, noremap = true, expr = false})
        if not cfg.user_maps_only and vim.fn.hasmapto('<Plug>' .. plug, "v") == 0 then
            vim.api.nvim_buf_set_keymap(0, 'v', '<LocalLeader>' .. combo, '<Esc>' .. tg, {silent = true, noremap = true, expr = false})
        end
    end
    if cfg.insert_mode_cmds and mode:find("i") then
        vim.api.nvim_buf_set_keymap(0, 'i', '<Plug>' .. plug, '<Esc>' .. tg .. il, {silent = true, noremap = true, expr = false})
        if not cfg.user_maps_only and vim.fn.hasmapto('<Plug>' .. plug, "i") == 0 then
            vim.api.nvim_buf_set_keymap(0, 'i', '<LocalLeader>' .. combo, '<Esc>' .. tg .. il, {silent = true, noremap = true, expr = false})
        end
    end
end

M.control = function()
    -- List space, clear console, clear all
    M.create('nvi', 'RListSpace',    'rl', ':lua require("r.send").cmd("ls()")')
    M.create('nvi', 'RClearConsole', 'rr', ':call RClearConsole()')
    M.create('nvi', 'RClearAll',     'rm', ':call RClearAll()')

    -- Print, names, structure
    M.create('ni', 'RObjectPr',    'rp', ':call RAction("print")')
    M.create('ni', 'RObjectNames', 'rn', ':call RAction("nvim.names")')
    M.create('ni', 'RObjectStr',   'rt', ':call RAction("str")')
    M.create('ni', 'RViewDF',      'rv', ':call RAction("viewobj")')
    -- M.create('ni', 'RViewDFs',     'vs', ':call RAction("viewobj", ", howto=''split''")')
    -- M.create('ni', 'RViewDFv',     'vv', ':call RAction("viewobj", ", howto=''vsplit''")')
    -- M.create('ni', 'RViewDFa',     'vh', ':call RAction("viewobj", ", howto=''above 7split'', nrows=6")')
    M.create('ni', 'RDputObj',     'td', ':call RAction("dputtab")')

    M.create('v', 'RObjectPr',     'rp', ':call RAction("print", "v")')
    M.create('v', 'RObjectNames',  'rn', ':call RAction("nvim.names", "v")')
    M.create('v', 'RObjectStr',    'rt', ':call RAction("str", "v")')
    M.create('v', 'RViewDF',       'rv', ':call RAction("viewobj", "v")')
    -- M.create('v', 'RViewDFs',      'vs', ':call RAction("viewobj", "v", ", howto=''split''")')
    -- M.create('v', 'RViewDFv',      'vv', ':call RAction("viewobj", "v", ", howto=''vsplit''")')
    -- M.create('v', 'RViewDFa',      'vh', ':call RAction("viewobj", "v", ", howto=''above 7split'', nrows=6")')
    M.create('v', 'RDputObj',      'td', ':call RAction("dputtab", "v")')

    -- Arguments, example, help
    M.create('nvi', 'RShowArgs',   'ra', ':call RAction("args")')
    M.create('nvi', 'RShowEx',     're', ':call RAction("example")')
    M.create('nvi', 'RHelp',       'rh', ':call RAction("help")')

    -- Summary, plot, both
    M.create('ni', 'RSummary',     'rs', ':call RAction("summary")')
    M.create('ni', 'RPlot',        'rg', ':call RAction("plot")')
    M.create('ni', 'RSPlot',       'rb', ':call RAction("plotsumm")')

    M.create('v', 'RSummary',      'rs', ':call RAction("summary", "v")')
    M.create('v', 'RPlot',         'rg', ':call RAction("plot", "v")')
    M.create('v', 'RSPlot',        'rb', ':call RAction("plotsumm", "v")')

    -- Object Browser
    M.create('nvi', 'RUpdateObjBrowser', 'ro', ':call RObjBrowser()')
    M.create('nvi', 'ROpenLists',        'r=', ':call RBrOpenCloseLs("O")')
    M.create('nvi', 'RCloseLists',       'r-', ':call RBrOpenCloseLs("C")')

    -- Render script with rmarkdown
    M.create('nvi', 'RMakeRmd',    'kr', ':call RMakeRmd("default")')
    M.create('nvi', 'RMakeAll',    'ka', ':call RMakeRmd("all")')
    if vim.o.filetype == "quarto" then
        M.create('nvi', 'RMakePDFK',   'kp', ':call RMakeRmd("pdf")')
        M.create('nvi', 'RMakePDFKb',  'kl', ':call RMakeRmd("beamer")')
        M.create('nvi', 'RMakeWord',   'kw', ':call RMakeRmd("docx")')
        M.create('nvi', 'RMakeHTML',   'kh', ':call RMakeRmd("html")')
        M.create('nvi', 'RMakeODT',    'ko', ':call RMakeRmd("odt")')
    else
        M.create('nvi', 'RMakePDFK',   'kp', ':call RMakeRmd("pdf_document")')
        M.create('nvi', 'RMakePDFKb',  'kl', ':call RMakeRmd("beamer_presentation")')
        M.create('nvi', 'RMakeWord',   'kw', ':call RMakeRmd("word_document")')
        M.create('nvi', 'RMakeHTML',   'kh', ':call RMakeRmd("html_document")')
        M.create('nvi', 'RMakeODT',    'ko', ':call RMakeRmd("odt_document")')
    end
end

M.start = function()
    -- Start
    M.create('nvi', 'RStart',       'rf', ':lua require("r.run").start_R("R")')
    M.create('nvi', 'RCustomStart', 'rc', ':lua require("r.run").start_R("custom")')

    -- Close
    M.create('nvi', 'RClose',       'rq', ":lua require('r.run').quit_R('nosave')")
    M.create('nvi', 'RSaveClose',   'rw', ":lua require('r.run').quit_R('save')")
end

M.edit = function()
    -- Edit
    -- Replace <M--> with ' <- '
    if cfg.assign then
        vim.api.nvim_buf_set_keymap(0, 'i', cfg.assign_map, '<Esc>:lua require("r.edit").assign()<CR>a', {silent = true})
    end
end

M.send = function()
    -- Block
    M.create('ni', 'RSendMBlock',     'bb', ':call SendMBlockToR("silent", "stay")')
    M.create('ni', 'RESendMBlock',    'be', ':call SendMBlockToR("echo", "stay")')
    M.create('ni', 'RDSendMBlock',    'bd', ':call SendMBlockToR("silent", "down")')
    M.create('ni', 'REDSendMBlock',   'ba', ':call SendMBlockToR("echo", "down")')

    -- Function
    M.create('nvi', 'RSendFunction',  'ff', ':call SendFunctionToR("silent", "stay")')
    M.create('nvi', 'RDSendFunction', 'fe', ':call SendFunctionToR("echo", "stay")')
    M.create('nvi', 'RDSendFunction', 'fd', ':call SendFunctionToR("silent", "down")')
    M.create('nvi', 'RDSendFunction', 'fa', ':call SendFunctionToR("echo", "down")')

    -- Selection
    M.create('n', 'RSendSelection',   'ss', ':call SendSelectionToR("silent", "stay", "normal")')
    M.create('n', 'RESendSelection',  'se', ':call SendSelectionToR("echo", "stay", "normal")')
    M.create('n', 'RDSendSelection',  'sd', ':call SendSelectionToR("silent", "down", "normal")')
    M.create('n', 'REDSendSelection', 'sa', ':call SendSelectionToR("echo", "down", "normal")')

    M.create('v', 'RSendSelection',   'ss', ':call SendSelectionToR("silent", "stay")')
    M.create('v', 'RESendSelection',  'se', ':call SendSelectionToR("echo", "stay")')
    M.create('v', 'RDSendSelection',  'sd', ':call SendSelectionToR("silent", "down")')
    M.create('v', 'REDSendSelection', 'sa', ':call SendSelectionToR("echo", "down")')
    M.create('v', 'RSendSelAndInsertOutput', 'so', ':call SendSelectionToR("echo", "stay", "NewtabInsert")')

    -- Paragraph
    M.create('ni', 'RSendParagraph',   'pp', ':lua require("r.send").paragraph("silent", "stay")')
    M.create('ni', 'RESendParagraph',  'pe', ':lua require("r.send").paragraph("echo", "stay")')
    M.create('ni', 'RDSendParagraph',  'pd', ':lua require("r.send").paragraph("silent", "down")')
    M.create('ni', 'REDSendParagraph', 'pa', ':lua require("r.send").paragraph("echo", "down")')

    if vim.o.filetype == "rnoweb" or vim.o.filetype == "rmd" or vim.o.filetype == "quarto" or vim.o.filetype == "rrst" then
        M.create('ni', 'RSendChunkFH', 'ch', ':call SendFHChunkToR()')
    end

    -- *Line*
    M.create('ni',  'RSendLine', 'l', ':lua require("r.send").line("stay")')
    M.create('ni0', 'RDSendLine', 'd', ':lua require("r.send").line("down")')
    M.create('ni0', '(RDSendLineAndInsertOutput)', 'o', ':call SendLineToRAndInsertOutput()')
    M.create('v',   '(RDSendLineAndInsertOutput)', 'o', ':call RWarningMsg("This command does not work over a selection of lines.")')
    M.create('i',   'RSendLAndOpenNewOne', 'q', ':lua require("r.send").line("newline")')
    M.create('ni.', 'RSendMotion', 'm', ':set opfunc=SendMotionToR<CR>g@')
    M.create('n',   'RNLeftPart', 'r<left>', ':call RSendPartOfLine("left", 0)')
    M.create('n',   'RNRightPart', 'r<right>', ':call RSendPartOfLine("right", 0)')
    M.create('i',   'RILeftPart', 'r<left>', 'l:call RSendPartOfLine("left", 1)')
    M.create('i',   'RIRightPart', 'r<right>', 'l:call RSendPartOfLine("right", 1)')
    if vim.o.filetype == "r" then
        M.create('n', 'RSendAboveLines',  'su', ':require("r.send").above_lines()')
    end

    -- Debug
    M.create('n',   'RDebug', 'bg', ':call RAction("debug")')
    M.create('n',   'RUndebug', 'ud', ':call RAction("undebug")')
end

return M
