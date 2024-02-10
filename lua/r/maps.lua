local config = require("r.config").get_config()

-- stylua: ignore start

--- Create maps.
--- For each noremap we need a vnoremap including <Esc> before the :call,
--- otherwise nvim will call the function as many times as the number of selected
--- lines. If we put <Esc> in the noremap, nvim will bell.
---@param mode string Modes to which create maps (normal, visual and insert)
--- and whether the cursor have to go the beginning of the line
---@param plug string The "<Plug>" name.
---@param combo string Key combination.
---@param target string The command or function to be called.
local create_maps = function(mode, plug, combo, target)
    if config.disable_cmds.plug then return end
    local tg
    local il
    if mode:find("0") then
        tg = target .. "<CR>0"
        il = "i"
    elseif mode:find("%.") then
        tg = target
        il = "a"
    else
        tg = target .. "<CR>"
        il = "a"
    end
    local opts = { silent = true, noremap = true, expr = false }
    if mode:find("n") then
        vim.api.nvim_buf_set_keymap(0, "n", "<Plug>" .. plug, tg, opts)
        if not config.user_maps_only and vim.fn.hasmapto("<Plug>" .. plug, "n") == 0 then
            vim.api.nvim_buf_set_keymap(0, "n", "<LocalLeader>" .. combo, "<Plug>" .. plug, opts)
        end
    end
    if mode:find("v") then
        vim.api.nvim_buf_set_keymap(0, "v", "<Plug>" .. plug, "<Esc>" .. tg, opts)
        if not config.user_maps_only and vim.fn.hasmapto("<Plug>" .. plug, "v") == 0 then
            vim.api.nvim_buf_set_keymap(0, "v", "<LocalLeader>" .. combo, "<Esc>" .. tg, opts)
        end
    end
    if config.insert_mode_cmds and mode:find("i") then
        vim.api.nvim_buf_set_keymap(0, "i", "<Plug>" .. plug, "<Esc>" .. tg .. il, opts)
        if not config.user_maps_only and vim.fn.hasmapto("<Plug>" .. plug, "i") == 0 then
            vim.api.nvim_buf_set_keymap(0, "i", "<LocalLeader>" .. combo, "<Esc>" .. tg .. il, opts)
        end
    end
end

local control = function(file_type)
    -- List space, clear console, clear all
    create_maps("nvi", "RListSpace",        "rl", "<Cmd>lua require('r.send').cmd('ls()')")
    create_maps("nvi", "RClearConsole",     "rr", "<Cmd>lua require('r.run').clear_console()")
    create_maps("nvi", "RClearAll",         "rm", "<Cmd>lua require('r.run').clear_all()")

    -- Print,          names,               structure
    create_maps("ni",  "RObjectPr",         "rp", "<Cmd>lua require('r.run').action('print')")
    create_maps("ni",  "RObjectNames",      "rn", "<Cmd>lua require('r.run').action('nvim.names')")
    create_maps("ni",  "RObjectStr",        "rt", "<Cmd>lua require('r.run').action('str')")
    create_maps("ni",  "RViewDF",           "rv", "<Cmd>lua require('r.run').action('viewobj')")
    create_maps("ni",  "RViewDFs",          "vs", "<Cmd>lua require('r.run').action('viewobj', ', howto=\"split\"')")
    create_maps("ni",  "RViewDFv",          "vv", "<Cmd>lua require('r.run').action('viewobj', ', howto=\"vsplit\"')")
    create_maps("ni",  "RViewDFa",          "vh", "<Cmd>lua require('r.run').action('viewobj', ', howto=\"above 7split\", nrows=6')")
    create_maps("ni",  "RDputObj",          "td", "<Cmd>lua require('r.run').action('dputtab')")

    create_maps("v",   "RObjectPr",         "rp", "<Cmd>lua require('r.run').action('print', 'v')")
    create_maps("v",   "RObjectNames",      "rn", "<Cmd>lua require('r.run').action('nvim.names', 'v')")
    create_maps("v",   "RObjectStr",        "rt", "<Cmd>lua require('r.run').action('str', 'v')")
    create_maps("v",   "RViewDF",           "rv", "<Cmd>lua require('r.run').action('viewobj', 'v')")
    create_maps("v",   "RViewDFs",          "vs", "<Cmd>lua require('r.run').action('viewobj', 'v', ', howto=\"split\"')")
    create_maps("v",   "RViewDFv",          "vv", "<Cmd>lua require('r.run').action('viewobj', 'v', ', howto=\"vsplit\"')")
    create_maps("v",   "RViewDFa",          "vh", "<Cmd>lua require('r.run').action('viewobj', 'v', ', howto=\"above 7split\", nrows=6')")
    create_maps("v",   "RDputObj",          "td", "<Cmd>lua require('r.run').action('dputtab', 'v')")

    -- Arguments,      example,             help
    create_maps("nvi", "RShowArgs",         "ra", "<Cmd>lua require('r.run').action('args')")
    create_maps("nvi", "RShowEx",           "re", "<Cmd>lua require('r.run').action('example')")
    create_maps("nvi", "RHelp",             "rh", "<Cmd>lua require('r.run').action('help')")

    -- Summary,        plot,                both
    create_maps("ni",  "RSummary",          "rs", "<Cmd>lua require('r.run').action('summary')")
    create_maps("ni",  "RPlot",             "rg", "<Cmd>lua require('r.run').action('plot')")
    create_maps("ni",  "RSPlot",            "rb", "<Cmd>lua require('r.run').action('plotsumm')")

    create_maps("v",   "RSummary",          "rs", "<Cmd>lua require('r.run').action('summary', 'v')")
    create_maps("v",   "RPlot",             "rg", "<Cmd>lua require('r.run').action('plot', 'v')")
    create_maps("v",   "RSPlot",            "rb", "<Cmd>lua require('r.run').action('plotsumm', 'v')")

    -- Object Browser
    create_maps("nvi", "RUpdateObjBrowser", "ro", "<Cmd>lua require('r.browser').start()")
    create_maps("nvi", "ROpenLists",        "r=", "<Cmd>lua require('r.browser').open_close_lists('O')")
    create_maps("nvi", "RCloseLists",       "r-", "<Cmd>lua require('r.browser').open_close_lists('C')")

    -- Render script with rmarkdown
    create_maps("nvi", "RMakeRmd",          "kr", "<Cmd>lua require('r.rmd').make('default')")
    create_maps("nvi", "RMakeAll",          "ka", "<Cmd>lua require('r.rmd').make('all')")
    if file_type == "quarto" then
        create_maps("nvi", "RMakePDFK",  "kp", "<Cmd>lua require('r.rmd').make('pdf')")
        create_maps("nvi", "RMakePDFKb", "kl", "<Cmd>lua require('r.rmd').make('beamer')")
        create_maps("nvi", "RMakeWord",  "kw", "<Cmd>lua require('r.rmd').make('docx')")
        create_maps("nvi", "RMakeHTML",  "kh", "<Cmd>lua require('r.rmd').make('html')")
        create_maps("nvi", "RMakeODT",   "ko", "<Cmd>lua require('r.rmd').make('odt')")
    else
        create_maps("nvi", "RMakePDFK",  "kp", "<Cmd>lua require('r.rmd').make('pdf_document')")
        create_maps("nvi", "RMakePDFKb", "kl", "<Cmd>lua require('r.rmd').make('beamer_presentation')")
        create_maps("nvi", "RMakeWord",  "kw", "<Cmd>lua require('r.rmd').make('word_document')")
        create_maps("nvi", "RMakeHTML",  "kh", "<Cmd>lua require('r.rmd').make('html_document')")
        create_maps("nvi", "RMakeODT",   "ko", "<Cmd>lua require('r.rmd').make('odt_document')")
    end
end

local start = function()
    -- Start
    create_maps("nvi", "RStart",       "rf", "<Cmd>lua require('r.run').start_R('R')")
    create_maps("nvi", "RCustomStart", "rc", "<Cmd>lua require('r.run').start_R('custom')")

    -- Close
    create_maps("nvi", "RClose",       "rq", "<Cmd>lua require('r.run').quit_R('nosave')")
    create_maps("nvi", "RSaveClose",   "rw", "<Cmd>lua require('r.run').quit_R('save')")
end

local edit = function()
    -- Edit
    -- Replace <M--> with ' <- '
    if config.assign then
        vim.api.nvim_buf_set_keymap(0, "i", config.assign_map,
            '<Cmd>lua require("r.edit").assign()<CR>', { silent = true })
    end
    create_maps("nvi", "RSetwd", "rd", "<Cmd>lua require('r.run').setwd()")
end

local send = function(file_type)
    -- Block
    create_maps("ni",  "RSendMBlock",      "bb", "<Cmd>lua require('r.send').marked_block(false)")
    create_maps("ni",  "RDSendMBlock",     "bd", "<Cmd>lua require('r.send').marked_block(true)")

    -- Function
    -- Not currently implemented
    -- create_maps("nvi", "RSendFunction",    "ff", "<Cmd>lua require('r.send').fun(false)")
    -- create_maps("nvi", "RDSendFunction",   "fd", "<Cmd>lua require('r.send').fun(true)")

    -- Selection
    create_maps("nv",   "RSendSelection",   "ss", "<Cmd>lua require('r.send').selection(false)")
    create_maps("nv",   "RDSendSelection",  "sd", "<Cmd>lua require('r.send').selection(true)")

    -- Paragraph
    create_maps("ni", "RSendParagraph",   "pp", "<Cmd>lua require('r.send').paragraph(false)")
    create_maps("ni", "RDSendParagraph",  "pd", "<Cmd>lua require('r.send').paragraph(true)")

    if file_type == "rnoweb" or file_type == "rmd" or file_type == "quarto" then
        create_maps("ni", "RSendChunkFH", "ch", "<Cmd>lua require('r.send').chunks_up_to_here()")
    end

    -- *Line*
    create_maps("ni",  "RSendLine",           "l",        "<Cmd>lua require('r.send').line(false)")
    create_maps("ni0", "RDSendLine",          "d",        "<Cmd>lua require('r.send').line(true)")
    create_maps("ni0", "(RInsertLineOutput)", "o",        "<Cmd>lua require('r.run').insert_commented()")
    create_maps("v",   "(RInsertLineOutput)", "o",        "<Cmd>lua require('r').warn('This command does not work over a selection of lines.')")
    create_maps("i",   "RSendLAndOpenNewOne", "q",        "<Cmd>lua require('r.send').line('newline')")
    create_maps("ni.", "RSendMotion",         "m",        "<Cmd>set opfunc=v:lua.require('r.send').motion<CR>g@")
    create_maps("n",   "RNLeftPart",          "r<left>",  "<Cmd>lua require('r.send').line_part('left',  false)")
    create_maps("n",   "RNRightPart",         "r<right>", "<Cmd>lua require('r.send').line_part('right', false)")
    create_maps("i",   "RILeftPart",          "r<left>",  "<Cmd>lua require('r.send').line_part('left',  true)")
    create_maps("i",   "RIRightPart",         "r<right>", "<Cmd>lua require('r.send').line_part('right', true)")
    if file_type == "r" then
        create_maps("n",   "RSendAboveLines", "su", "<Cmd>lua require('r.send').above_lines()")
        create_maps("ni",  "RSendFile",       "aa", "<Cmd>lua require('r.send').source_file('silent')")
        create_maps("ni",  "RESendFile",      "ae", "<Cmd>lua require('r.send').source_file('echo')")
        create_maps("ni",  "RShowRout",       "ao", "<Cmd>lua require('r').show_R_out()")
    end
    if file_type == "rmd" or file_type == "quarto" then
        create_maps("nvi", "RKnit",           "kn", "<Cmd>lua require('r.run').knit()")
        create_maps("ni",  "RSendChunk",      "cc", "<Cmd>lua require('r.rmd').send_R_chunk(false)")
        create_maps("ni",  "RDSendChunk",     "cd", "<Cmd>lua require('r.rmd').send_R_chunk(true)")
        create_maps("n",   "RNextRChunk",     "gn", "<Cmd>lua require('r.rmd').next_chunk()")
        create_maps("n",   "RPreviousRChunk", "gN", "<Cmd>lua require('r.rmd').previous_chunk()")
    end
    if file_type == "quarto" then
        create_maps("n",   "RQuartoRender",   "qr", "<Cmd>lua require('r.quarto').command('render')")
        create_maps("n",   "RQuartoPreview",  "qp", "<Cmd>lua require('r.quarto').command('preview')")
        create_maps("n",   "RQuartoStop",     "qs", "<Cmd>lua require('r.quarto').command('stop')")
    end
    if file_type == "rnoweb" then
        create_maps("nvi", "RSweave",         "sw", "<Cmd>lua require('r.rnw').weave('nobib',  false, false)")
        create_maps("nvi", "RMakePDF",        "sp", "<Cmd>lua require('r.rnw').weave('nobib',  false, true)")
        create_maps("nvi", "RBibTeX",         "sb", "<Cmd>lua require('r.rnw').weave('bibtex', false, true)")
        if config.rm_knit_cache then
            create_maps("nvi", "RKnitRmCache", "kr", "<Cmd>lua require('r.rnw').rm_knit_cache()")
        end
        create_maps("nvi", "RKnit",        "kn", "<Cmd>lua require('r.rnw').weave('nobib',  true, false)")
        create_maps("nvi", "RMakePDFK",    "kp", "<Cmd>lua require('r.rnw').weave('nobib',  true, true)")
        create_maps("nvi", "RBibTeXK",     "kb", "<Cmd>lua require('r.rnw').weave('bibtex', true, true)")
        create_maps("ni",  "RSendChunk",   "cc", "<Cmd>lua require('r.rnw').send_chunk(false)")
        create_maps("ni",  "RDSendChunk",  "cd", "<Cmd>lua require('r.rnw').send_chunk(true)")
        create_maps("nvi", "ROpenPDF",     "op", "<Cmd>lua require('r.pdf').open('Get Master')")
        if config.synctex then
            create_maps("ni", "RSyncFor", "gp", "<Cmd>lua require('r.rnw').SyncTeX_forward(false)")
            create_maps("ni", "RGoToTeX", "gt", "<Cmd>lua require('r.rnw').SyncTeX_forward(true)")
        end
        create_maps("n", "RNextRChunk",     "gn", "<Cmd>lua require('r.rnw').next_chunk()")
        create_maps("n", "RPreviousRChunk", "gN", "<Cmd>lua require('r.rnw').previous_chunk()")
    end
    if file_type == "rdoc" then
        local opts = { silent = true, noremap = true, expr = false }
        create_maps("n", "RDocExSection", "ge", "<Cmd>lua require('r.rdoc').go_to_ex_section()")
        vim.api.nvim_buf_set_keymap(0, "n", "q", "<Cmd>quit<CR>", opts)
    end
end

-- stylua: ignore end

local M = {}

M.create = function(file_type)
    control(file_type)
    if file_type == "rbrowser" then return end
    send(file_type)
    if file_type == "rdoc" then return end
    start()
    edit()
end

return M
