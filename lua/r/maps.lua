local config = require("r.config").get_config()
local warn = require("r.log").warn

-- stylua: ignore start

local map_desc = {
    RCustomStart        = { m = "", k = "", c = "Start",    d = "Ask user to enter parameters to start R" },
    RPackages           = { m = "", k = "", c = "Start",    d = "Install missing package" },
    RSaveClose          = { m = "", k = "", c = "Start",    d = "Quit R, saving the workspace" },
    RClose              = { m = "", k = "", c = "Start",    d = "Send to R: quit(save = 'no')" },
    RStart              = { m = "", k = "", c = "Start",    d = "Start R with default configuration or reopen terminal window" },
    RInsertAssign       = { m = "", k = "", c = "Edit",     d = "Insert ` <- `" },
    RInsertPipe         = { m = "", k = "", c = "Edit",     d = "Insert ` |>` (or ` %>%`)" },
    ROpenPDF            = { m = "", k = "", c = "Edit",     d = "Open the PDF generated from the current document" },
    RDputObj            = { m = "", k = "", c = "Edit",     d = "Run dput(<cword>) and show the output in a new tab" },
    RViewDF             = { m = "", k = "", c = "Edit",     d = "View the data.frame or matrix under cursor in a new tab" },
    RShowEx             = { m = "", k = "", c = "Edit",     d = "Extract the Examples section and paste it in a split window" },
    RSeparatePath       = { m = "", k = "", c = "Edit",     d = "Split the file path or the url under the cursor" },
    RFormatNumbers      = { m = "", k = "", c = "Edit",     d = "Add an 'L' suffix after numbers" },
    RFormatSubsetting   = { m = "", k = "", c = "Edit",     d = "Replace all the `$` subsetting operators with `[[`" },
    RmdInsertChunk      = { m = "", k = "", c = "Edit",     d = "Insert chunk delimiter" },
    RnwInsertChunk      = { m = "", k = "", c = "Edit",     d = "Insert chunk delimiter" },
    RNextRChunk         = { m = "", k = "", c = "Navigate", d = "Go to the next chunk of R code" },
    RGoToTeX            = { m = "", k = "", c = "Navigate", d = "Go the corresponding line in the generated LaTeX document" },
    RPreviousRChunk     = { m = "", k = "", c = "Navigate", d = "Go to the previous chunk of R code" },
    RSyncFor            = { m = "", k = "", c = "Navigate", d = "SyncTeX forward" },
    RInsertLineOutput   = { m = "", k = "", c = "Send",     d = "Ask R to evaluate the line and insert the output" },
    RSendChunkFH        = { m = "", k = "", c = "Send",     d = "Send all chunks of R code from the document's begin up to here" },
    RSendChunk          = { m = "", k = "", c = "Send",     d = "Send the current chunk of code to R" },
    RSendLAndOpenNewOne = { m = "", k = "", c = "Send",     d = "Send the current line and open a new one" },
    RSendLine           = { m = "", k = "", c = "Send",     d = "Send the current line to R" },
    RSendFile           = { m = "", k = "", c = "Send",     d = "Send the whole file to R" },
    RSendAboveLines     = { m = "", k = "", c = "Send",     d = "Send to R all lines above the current one" },
    RSendChain          = { m = "", k = "", c = "Send",     d = "Send to R the above chain of piped commands" },
    RDSendChunk         = { m = "", k = "", c = "Send",     d = "Send to R the current chunk of R code and move down to next chunk" },
    RDSendLine          = { m = "", k = "", c = "Send",     d = "Send to R the current line and move down to next line" },
    RSendMBlock         = { m = "", k = "", c = "Send",     d = "Send to R the lines between two marks" },
    RDSendMBlock        = { m = "", k = "", c = "Send",     d = "Send to R the lines between two marks and move to next line" },
    RSendMotion         = { m = "", k = "", c = "Send",     d = "Send to R the lines in a Vim motion" },
    RSendParagraph      = { m = "", k = "", c = "Send",     d = "Send to R the next consecutive non-empty lines" },
    RDSendParagraph     = { m = "", k = "", c = "Send",     d = "Send to R the next sequence of consecutive non-empty lines" },
    RILeftPart          = { m = "", k = "", c = "Send",     d = "Send to R the part of the line on the left of the cursor" },
    RNLeftPart          = { m = "", k = "", c = "Send",     d = "Send to R the part of the line on the left of the cursor" },
    RIRightPart         = { m = "", k = "", c = "Send",     d = "Send to R the part of the line on the right of the cursor" },
    RNRightPart         = { m = "", k = "", c = "Send",     d = "Send to R the part of the line on the right of the cursor" },
    RDSendSelection     = { m = "", k = "", c = "Send",     d = "Send to R visually selected lines or part of a line" },
    RSendSelection      = { m = "", k = "", c = "Send",     d = "Send visually selected lines of part of a line" },
    RSendCurrentFun     = { m = "", k = "", c = "Send",     d = "Send the current function" },
    RDSendCurrentFun    = { m = "", k = "", c = "Send",     d = "Send the current function and move the cursor to the end of the function definition" },
    RSendAllFun         = { m = "", k = "", c = "Send",     d = "Send all the top level functions in the current buffer" },
    RHelp               = { m = "", k = "", c = "Command",  d = "Ask for R documentation on the object under cursor" },
    RShowRout           = { m = "", k = "", c = "Command",  d = "R CMD BATCH the current document and show the output in a new tab" },
    RSPlot              = { m = "", k = "", c = "Command",  d = "Send to R command to run summary and plot with <cword> as argument" },
    RClearConsole       = { m = "", k = "", c = "Command",  d = "Send to R: <Ctrl-L>" },
    RDebug              = { m = "", k = "", c = "Command",  d = "Send to R: debug" },
    RUndebug            = { m = "", k = "", c = "Command",  d = "Send to R: undebug" },
    RListSpace          = { m = "", k = "", c = "Command",  d = "Send to R: ls()" },
    RShowArgs           = { m = "", k = "", c = "Command",  d = "Send to R: nvim.args(<cword>)" },
    RObjectNames        = { m = "", k = "", c = "Command",  d = "Send to R: nvim.names(<cword>)" },
    RPlot               = { m = "", k = "", c = "Command",  d = "Send to R: plot(<cword>)" },
    RObjectPr           = { m = "", k = "", c = "Command",  d = "Send to R: print(<cword>)" },
    RClearAll           = { m = "", k = "", c = "Command",  d = "Send to R: rm(list   = ls())" },
    RSetwd              = { m = "", k = "", c = "Command",  d = "Send to R setwd(<directory of current document>)" },
    RObjectStr          = { m = "", k = "", c = "Command",  d = "Send to R: str(<cword>)" },
    RSummary            = { m = "", k = "", c = "Command",  d = "Send to R: summary(<cword>)" },
    RKnitRmCache        = { m = "", k = "", c = "Weave",    d = "Delete files from knitr cache" },
    RMakePDFKb          = { m = "", k = "", c = "Weave",    d = "Knit the current document and generate a beamer presentation" },
    RMakeAll            = { m = "", k = "", c = "Weave",    d = "Knit the current document and generate all formats in the header" },
    RMakeHTML           = { m = "", k = "", c = "Weave",    d = "Knit the current document and generate an HTML document" },
    RMakeODT            = { m = "", k = "", c = "Weave",    d = "Knit the current document and generate an ODT document" },
    RMakePDFK           = { m = "", k = "", c = "Weave",    d = "Knit the current document and generate a PDF document" },
    RMakeWord           = { m = "", k = "", c = "Weave",    d = "Knit the current document and generate a Word document" },
    RMakeRmd            = { m = "", k = "", c = "Weave",    d = "Knit the current document and generate the default document format" },
    RKnit               = { m = "", k = "", c = "Weave",    d = "Knit the document" },
    RBibTeXK            = { m = "", k = "", c = "Weave",    d = "Knit the document, run bibtex and generate the PDF" },
    RQuartoPreview      = { m = "", k = "", c = "Weave",    d = "Send to R: quarto::quarto_preview()" },
    RQuartoStop         = { m = "", k = "", c = "Weave",    d = "Send to R: quarto::quarto_preview_stop()" },
    RQuartoRender       = { m = "", k = "", c = "Weave",    d = "Send to R: quarto::quarto_render()" },
    RSweave             = { m = "", k = "", c = "Weave",    d = "Sweave the current document" },
    RMakePDF            = { m = "", k = "", c = "Weave",    d = "Sweave the current document and generate a PDF document" },
    RBibTeX             = { m = "", k = "", c = "Weave",    d = "Sweave the document and run bibtex" },
    ROBCloseLists = { m = "", k = "", c = "Object_Browser", d = "Close S4 objects, lists and data.frames in the Object Browser" },
    ROBOpenLists =  { m = "", k = "", c = "Object_Browser", d = "Open S4 objects, lists and data.frames in the Object Browser" },
    ROBToggle =     { m = "", k = "", c = "Object_Browser", d = "Toggle the Object Browser" },
}

local map_list

local fill_map_list = function()
    local plg = ""
    local map = ""
    map_list = { n = {}, v = {}, i = {}}
    for _, mode in pairs({"n", "i", "v"}) do
        local txt = vim.fn.execute(mode .. "map")
        local lines = vim.split(txt, "\n")
        for _, v in pairs(lines) do
            if v:find("<Plug>R") and not v:find("^" .. mode .. "  <Plug>R") then
                plg = v:gsub(".*<Plug>R", "R")
                plg = plg:gsub(" .*", "")
                map = v:gsub("^" .. mode .. "  ", "")
                map = map:gsub(" .*", "")
                table.insert(map_list[mode], { plg, map })
            end
        end
    end
end

local get_map_to = function(plg, mode)
    for _, v in pairs(map_list[mode]) do
        if v[1] == plg then
            return v[2]
        end
    end
    return ""
end

local map_it = function(plug, mode, tgt, cmd, opts)
    if not string.find(map_desc[plug].m, mode) then
        map_desc[plug].m = map_desc[plug].m .. mode
    end
    vim.api.nvim_buf_set_keymap(0, mode, "<Plug>" .. plug, tgt, opts)

    local key = get_map_to(plug, mode)
    if key ~= "" then
        map_desc[plug].k = key
        return
    end

    if config.user_maps_only then
        map_desc[plug].k = "disabled"
        return
    end

    vim.api.nvim_buf_set_keymap(0, mode, cmd, "<Plug>" .. plug, opts)
    map_desc[plug].k = cmd
end

--- Create maps.
---@param mode string Modes to which create maps (normal, visual and insert)
--- and whether the cursor have to go the beginning of the line
---@param plug string The "<Plug>" name.
---@param combo string Key combination.
---@param target string The command or function to be called.
---@param esp number? Especial treatment: 1 (no <CR>), 2 (exceptional Insert mode command), or 3 no <LocalLeader>).
local create_maps = function(mode, plug, combo, target, esp)
    if not map_desc[plug] then
        warn("Missing <Plug> label in description table: '" .. plug .. "'")
        return
    end
    if vim.fn.index(config.disable_cmds, plug) > -1 then
        map_desc[plug].k = "disabled"
        return
    end

    local tgt = (esp and esp == 1) and target or target .. "<CR>"
    local cmd = (esp and esp == 3) and combo or "<LocalLeader>" .. combo
    local opts = { silent = true, noremap = true, expr = false, desc = map_desc[plug].d }

    if mode:find("n") then map_it(plug, "n", tgt, cmd, opts) end
    if mode:find("v") then map_it(plug, "v", tgt, cmd, opts) end
    if (config.insert_mode_cmds or (esp and esp > 1)) and mode:find("i") then
        map_it(plug, "i", tgt, cmd, opts)
    end
end

--- Create control maps
---@param file_type string
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
    create_maps("ni",  "RDputObj",          "td", "<Cmd>lua require('r.run').action('dputtab')")

    create_maps("v",   "RObjectPr",         "rp", "<Cmd>lua require('r.run').action('print', 'v')")
    create_maps("v",   "RObjectNames",      "rn", "<Cmd>lua require('r.run').action('nvim.names', 'v')")
    create_maps("v",   "RObjectStr",        "rt", "<Cmd>lua require('r.run').action('str', 'v')")
    create_maps("v",   "RViewDF",           "rv", "<Cmd>lua require('r.run').action('viewobj', 'v')")
    create_maps("v",   "RDputObj",          "td", "<Cmd>lua require('r.run').action('dputtab', 'v')")

    create_maps("ni", "RPackages",          "ip", "<Cmd>lua require('r.packages').install_missing_packages()")

    -- Arguments,      example,             help
    create_maps("nvi", "RShowArgs",         "ra", "<Cmd>lua require('r.run').action('args')")
    create_maps("nvi", "RShowEx",           "re", "<Cmd>lua require('r.run').action('example')")
    create_maps("nvi", "RHelp",             "rh", "<Cmd>lua require('r.run').action('help')")

    -- Summary,        plot,                both
    create_maps("ni",  "RSummary",          "rs", "<Cmd>lua require('r.run').action('summary')")
    create_maps("ni",  "RPlot",             "rg", "<Cmd>lua require('r.run').action('plot')")
    create_maps("ni",  "RSPlot",            "rb", "<Cmd>lua require('r.run').action('plotsumm')")
    create_maps("ni",  "RDebug",            "bg", "<Cmd>lua require('r.run').action('debug')")
    create_maps("ni",  "RUndebug",          "ud", "<Cmd>lua require('r.run').action('undebug')")

    create_maps("v",   "RSummary",          "rs", "<Cmd>lua require('r.run').action('summary', 'v')")
    create_maps("v",   "RPlot",             "rg", "<Cmd>lua require('r.run').action('plot', 'v')")
    create_maps("v",   "RSPlot",            "rb", "<Cmd>lua require('r.run').action('plotsumm', 'v')")
    create_maps("v",   "RDebug",            "bg", "<Cmd>lua require('r.run').action('debug', 'v')")
    create_maps("v",   "RUndebug",          "ud", "<Cmd>lua require('r.run').action('undebug', 'v')")

    -- Object Browser
    create_maps("nvi", "ROBToggle",         "ro", "<Cmd>lua require('r.browser').start()")
    create_maps("nvi", "ROBOpenLists",      "r=", "<Cmd>lua require('r.browser').open_close_lists('O')")
    create_maps("nvi", "ROBCloseLists",     "r-", "<Cmd>lua require('r.browser').open_close_lists('C')")

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

local edit = function(file_type)
    create_maps("i", "RInsertPipe", ",", "<Cmd>lua require('r.edit').pipe()", 2)
    create_maps("i", "RInsertAssign", "<M-->", "<Cmd>lua require('r.edit').assign()", 3)
    if file_type == "rmd" or file_type == "quarto" then
        create_maps("i", "RmdInsertChunk", "<M-r>", "<Cmd>lua require('r.rmd').write_chunk()", 3)
    end
    if file_type == "rnoweb" then
        create_maps("i", "RnwInsertChunk", "<M-r>", "<Cmd>lua require('r.rnw').write_chunk()", 3)
    end
    create_maps("nvi", "RSetwd", "rd", "<Cmd>lua require('r.run').setwd()")

    create_maps("nvi", "RSeparatePath",    "sp", "<Cmd>lua require('r.path').separate()")

    -- Format functions
    create_maps("nvi", "RFormatNumbers",    "cn", "<Cmd>lua require('r.format.numbers').formatnum()")
    create_maps("nvi", "RFormatSubsetting",    "cs", "<Cmd>lua require('r.format.brackets').formatsubsetting()")
end

local send = function(file_type)
    -- Block
    create_maps("ni",  "RSendMBlock",      "bb", "<Cmd>lua require('r.send').marked_block(false)")
    create_maps("ni",  "RDSendMBlock",     "bd", "<Cmd>lua require('r.send').marked_block(true)")

    -- Function
    create_maps("nvi", "RSendAllFun",    "fa", "<Cmd>lua require('r.send').funs(true, false)")
    create_maps("nvi", "RSendCurrentFun",   "fc", "<Cmd>lua require('r.send').funs(false, false)")
    create_maps("nvi", "RDSendCurrentFun",   "fd", "<Cmd>lua require('r.send').funs(false, true)")

    -- Pipe chain breaker
    create_maps("nv", "RSendChain",      "sc", "<Cmd>lua require('r.send').chain()")

    -- Selection
    create_maps("nv", "RSendSelection",  "ss", "<Cmd>lua require('r.send').selection(false)")
    create_maps("nv", "RDSendSelection", "sd", "<Cmd>lua require('r.send').selection(true)")

    -- Paragraph
    create_maps("ni", "RSendParagraph",  "pp", "<Cmd>lua require('r.send').paragraph(false)")
    create_maps("ni", "RDSendParagraph", "pd", "<Cmd>lua require('r.send').paragraph(true)")

    -- *Line*
    create_maps("ni",  "RSendLine",           "l",        "<Cmd>lua require('r.send').line(false)")
    create_maps("ni",  "RDSendLine",          "d",        "<Cmd>lua require('r.send').line(true)")
    create_maps("ni",  "RInsertLineOutput",   "o",        "<Cmd>lua require('r.run').insert_commented()")
    create_maps("v",   "RInsertLineOutput",   "o",        "<Cmd>lua require('r').warn('This command does not work over a selection of lines.')")
    create_maps("i",   "RSendLAndOpenNewOne", "q",        "<Cmd>lua require('r.send').line('newline')")
    create_maps("ni.", "RSendMotion",         "m",        "<Cmd>set opfunc=v:lua.require'r.send'.motion<CR>g@", 1)
    create_maps("n",   "RNLeftPart",          "r<left>",  "<Cmd>lua require('r.send').line_part('left',  false)")
    create_maps("n",   "RNRightPart",         "r<right>", "<Cmd>lua require('r.send').line_part('right', false)")
    create_maps("i",   "RILeftPart",          "r<left>",  "<Cmd>lua require('r.send').line_part('left',  true)")
    create_maps("i",   "RIRightPart",         "r<right>", "<Cmd>lua require('r.send').line_part('right', true)")
    if file_type == "r" then
        create_maps("n",   "RSendAboveLines", "su", "<Cmd>lua require('r.send').above_lines()")
        create_maps("ni",  "RSendFile",       "aa", "<Cmd>lua require('r.send').source_file()")
        create_maps("ni",  "RShowRout",       "ao", "<Cmd>lua require('r').show_R_out()")
    end
    if file_type == "rmd" or file_type == "quarto" then
        create_maps("nvi", "RKnit",           "kn", "<Cmd>lua require('r.run').knit()")
        create_maps("ni",  "RSendChunk",      "cc", "<Cmd>lua require('r.rmd').send_current_chunk(false)")
        create_maps("ni",  "RDSendChunk",     "cd", "<Cmd>lua require('r.rmd').send_current_chunk(true)")
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
    if file_type == "rnoweb" or file_type == "rmd" or file_type == "quarto" then
        create_maps("ni", "RSendChunkFH", "ch", "<Cmd>lua require('r.send').chunks_up_to_here()")
        if config.rm_knit_cache then
            create_maps("nvi", "RKnitRmCache", "kc", "<Cmd>lua require('r.rnw').rm_knit_cache()")
        end
    end
    if file_type == "rdoc" then
        vim.api.nvim_buf_set_keymap(0, "n", "q", "<Cmd>quit<CR>",
            { silent = true, noremap = true, expr = false, desc = "Close this window" })
    end
end

-- stylua: ignore end

local M = {}

M.create = function(file_type)
    if not map_list then fill_map_list() end
    control(file_type)
    if file_type == "rbrowser" then return end
    send(file_type)
    if file_type == "rdoc" then return end
    start()
    edit(file_type)
end

M.show_map_desc = function()
    local label_w = 1
    local key_w = 1
    for k, v in pairs(map_desc) do
        if #k >= label_w then label_w = #k + 1 end
        if #v.k >= key_w then key_w = #v.k + 1 end
    end
    local lw = tostring(label_w)
    local kw = tostring(key_w)

    local cat = {
        "Start",
        "Edit",
        "Navigate",
        "Send",
        "Command",
        "Weave",
        "Object_Browser",
    }
    local bycat = {}
    for _, c in pairs(cat) do
        bycat[c] = {}
    end
    for k, v in pairs(map_desc) do
        table.insert(bycat[v.c], { k, v.m, v.k, v.d })
    end

    local map_key_desc = {}
    for _, c in pairs(cat) do
        table.insert(map_key_desc, { c .. "\n", "Title" })
        for _, v in pairs(bycat[c]) do
            table.insert(
                map_key_desc,
                { string.format("  %-0" .. lw .. "s", v[1]), "Identifier" }
            )
            table.insert(map_key_desc, { string.format("  %-04s", v[2]), "Type" })
            local keymap = v[3] or " "
            local syngrp = keymap == "disabled" and "Comment" or "Special"
            local modes = vim.split(v[2], "")
            for _, m in pairs(modes) do
                if get_map_to(v[1], m) ~= "" then
                    syngrp = "String"
                    break
                end
            end
            table.insert(map_key_desc, {
                string.format("%-0" .. kw .. "s", keymap),
                syngrp,
            })
            table.insert(map_key_desc, { v[4] .. "\n" })
        end
    end

    local buf = vim.api.nvim_create_buf(false, true) -- no file, scratch buffer
    local ns = vim.api.nvim_create_namespace("RMapsDesc")
    local row = -1
    local cs = {}
    local ce = {}
    local line = ""
    local hls = {}
    for _, text_hl in pairs(map_key_desc) do
        local text = text_hl[1]:gsub("\n", "")
        line = line .. text
        local hl = text_hl[2]
        if hl == "Title" or hl == "Identifier" or row == -1 then -- start new line on "Title" or "Identifier"
            row = row + 1
        end
        if hl == "Title" then -- on "Title" write to buffer
            vim.api.nvim_buf_set_lines(buf, row, row, false, { line })
            if vim.fn.has("nvim-0.11") == 1 then
                vim.hl.range(buf, ns, hl, { row, 0 }, { row, #line }, {})
            else
                vim.api.nvim_buf_add_highlight(buf, -1, hl, row, 0, #line)
            end
            line = ""
        elseif hl == "Identifier" then
            cs = { 0 }
            ce = { #text }
            table.insert(hls, hl)
        elseif hl then
            table.insert(cs, ce[#ce])
            table.insert(ce, #line)
            table.insert(hls, hl)
        else -- hl is nil so it is the description so it's eol so write to buffer with appropriate highlights
            vim.api.nvim_buf_set_lines(buf, row, row, false, { line })
            if vim.fn.has("nvim-0.11") == 1 then
                vim.hl.range(buf, ns, hls[1], { row, cs[1] }, { row, ce[1] }, {})
                vim.hl.range(buf, ns, hls[2], { row, cs[2] }, { row, ce[2] }, {})
                vim.hl.range(buf, ns, hls[3], { row, cs[3] }, { row, ce[3] }, {})
            else
                vim.api.nvim_buf_add_highlight(buf, -1, hls[1], row, cs[1], ce[1])
                vim.api.nvim_buf_add_highlight(buf, -1, hls[2], row, cs[2], ce[2])
                vim.api.nvim_buf_add_highlight(buf, -1, hls[3], row, cs[3], ce[3])
            end
            hls = {}
            line = ""
        end
    end

    vim.api.nvim_buf_set_keymap(buf, "n", "q", "<Cmd>q<CR>", {})
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_open_win(buf, true, { style = "minimal", split = "above" })
end

return M
