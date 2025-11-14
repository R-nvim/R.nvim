local inform = require("r.log").inform
local config = require("r.config").get_config()
local get_lang = require("r.utils").get_lang
local uv = vim.uv
local chunk_key = nil
local quarto = require("r.quarto")

local M = {}

--- Writes a new R code chunk at the current cursor position
M.write_chunk = function()
    local curpos = vim.api.nvim_win_get_cursor(0)
    if not curpos then return end
    local curline = vim.api.nvim_get_current_line()
    local lang = get_lang()

    -- Check if cursor is in an empty Markdown line
    if lang == "markdown" and curline == "" then
        -- Insert new R code chunk template
        vim.api.nvim_buf_set_lines(
            0,
            curpos[1] - 1,
            curpos[1] - 1,
            true,
            { "```{r}", "", "```", "" }
        )
        vim.api.nvim_win_set_cursor(0, { curpos[1] + 1, 1 })
        vim.schedule(require("r.quarto").hl_code_bg)
        return
    end

    -- Check if cursor is in an Markdown region
    if lang == "markdown" or lang == "markdown_inline" then
        -- inline R code within markdown text
        vim.api.nvim_set_current_line(
            curline:sub(1, curpos[2]) .. "`r `" .. curline:sub(curpos[2] + 1)
        )
        vim.api.nvim_win_set_cursor(0, { curpos[1], curpos[2] + 3 })
        return
    end

    -- Just insert the mapped key stroke
    if not chunk_key then
        chunk_key = require("r.utils").get_mapped_key("RmdInsertChunk")
    end
    if chunk_key then
        vim.api.nvim_set_current_line(
            curline:sub(1, curpos[2]) .. chunk_key .. curline:sub(curpos[2] + 1)
        )
        vim.api.nvim_win_set_cursor(0, { curpos[1], curpos[2] + #chunk_key })
    end
end

--- Sends the current R or Python code chunk to the R console for evaluation.
---@param m boolean If true, the cursor will move to the next code chunk after evaluation.
M.send_current_chunk = function(m)
    local bufnr = vim.api.nvim_get_current_buf()

    local chunks = quarto.get_current_code_chunk(bufnr)

    chunks = quarto.filter_supported_langs(chunks)

    if #chunks == 0 then
        inform(
            "No evaluable R or Python code chunk found at the current cursor position."
        )

        return
    end

    local codelines = quarto.codelines_from_chunks(chunks)
    local ok = require("r.send").source_lines(codelines, "chunk")

    if ok == 0 then return end
    if m == true then M.next_chunk() end
end

--- Navigates to the previous R or Python code chunk in the document.
-- This function searches backwards from the current cursor position for the start of
-- any R or Python code chunk.
---@return boolean
local go_to_previous = function()
    local curline = vim.api.nvim_win_get_cursor(0)[1]
    local chunks = quarto.get_chunks_above_cursor(vim.api.nvim_get_current_buf())
    chunks = quarto.filter_code_chunks_by_eval(chunks)
    chunks = quarto.filter_supported_langs(chunks)

    -- move the cursor to the previous chunk
    if #chunks > 0 then
        local prev_chunk = chunks[#chunks]
        vim.api.nvim_win_set_cursor(0, { prev_chunk.start_row + 1, 0 })
        return true
    else
        vim.api.nvim_win_set_cursor(0, { curline, 0 })
        inform("There is no previous R code chunk to go.")
        return false
    end
end

-- Call go_to_previous() as many times as requested by the user.
M.previous_chunk = function()
    local i = 0
    while i < vim.v.count1 do
        if not go_to_previous() then break end
        i = i + 1
    end
end

--- Navigates to the next R or Python code chunk in the document.
-- This function searches forward from the current cursor position for the start of any R or Python code chunk.
---@return boolean
local go_to_next = function()
    local chunks = quarto.get_chunks_below_cursor(vim.api.nvim_get_current_buf())
    chunks = quarto.filter_code_chunks_by_eval(chunks)
    chunks = quarto.filter_supported_langs(chunks)

    local row = vim.api.nvim_win_get_cursor(0)[1]

    -- Move the cursor to the next chunk
    if #chunks > 0 then
        local next_chunk = chunks[1]

        -- If the current chunk is a header, move the cursor to the start of the chunk.
        -- Otherwise, move the cursor to the line after the chunk header.
        if quarto.get_current_code_chunk(0).start_row == row then
            vim.api.nvim_win_set_cursor(0, { next_chunk.start_row, 0 })
        else
            vim.api.nvim_win_set_cursor(0, { next_chunk.start_row + 1, 0 })
        end

        return true
    else
        inform("There is no next code chunk to go.")
        return false
    end
end

-- Call go_to_next() as many times as requested by the user.
M.next_chunk = function()
    local i = 0
    while i < vim.v.count1 do
        if not go_to_next() then break end
        i = i + 1
    end
end

local last_params = ""

--- Check if the YAML field params exists and if it is new
--- @return string
M.params_status = function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    if lines[1] ~= "---" then
        if last_params == "" then return "unchanged" end
        last_params = ""
        return "deleted"
    end

    local i = 2
    while i < #lines do
        if lines[i] == "params:" then
            local cp = ""
            i = i + 1
            while i < #lines and lines[i]:sub(1, 1) == " " do
                cp = cp .. lines[i]
                i = i + 1
            end
            if last_params == cp then return "unchanged" end
            last_params = cp
            return "new"
        end
        if lines[i] == "---" then break end
        i = i + 1
    end
    if last_params ~= "" then
        last_params = ""
        return "deleted"
    end
    return "unchanged"
end

--- Get the params variable from the YAML metadata and send it to nvimcom which
--- will create the params list in the .GlobalEnv.
M.update_params = function()
    if not vim.g.R_Nvim_status then return end
    if vim.g.R_Nvim_status < 7 then return end
    if config.set_params == "no" then return end

    local p = M.params_status()
    if p == "new" then
        local bn = vim.api.nvim_buf_get_name(0)
        if config.is_windows then bn = bn:gsub("\\", "\\\\") end
        require("r.run").send_to_nvimcom("E", "nvimcom:::update_params('" .. bn .. "')")
    elseif p == "deleted" then
        require("r.run").send_to_nvimcom(
            "E",
            "nvimcom:::update_params('DeleteOldParams')"
        )
    end
end

-- Register params as empty. This function is called when R quits.
M.clean_params = function() last_params = "" end

local setup_chunk_hl = function()
    if config.quarto_chunk_hl.events == nil or config.quarto_chunk_hl.events == "" then
        config.quarto_chunk_hl.events = "BufEnter,InsertLeave"
    end
    if config.quarto_chunk_hl.virtual_title == nil then
        config.quarto_chunk_hl.virtual_title = true
    end

    if config.quarto_chunk_hl.bg == nil or config.quarto_chunk_hl.bg == "" then
        local hl = vim.api.nvim_get_hl(0, { name = "CursorColumn", create = false })
        if hl.bg then config.quarto_chunk_hl.bg = string.format("#%06x", hl.bg) end
    end
    local cbg = config.quarto_chunk_hl.bg
    vim.api.nvim_set_hl(0, "RCodeBlock", { bg = cbg })

    local hl = vim.api.nvim_get_hl(0, { name = "Comment", create = false })
    local col = hl.fg and string.format("#%06x", hl.fg) or "#afafff"
    vim.api.nvim_set_hl(0, "RCodeComment", { bg = cbg, fg = col })

    hl = vim.api.nvim_get_hl(0, { name = "Ignore", create = false })
    col = hl.fg and string.format("#%06x", hl.fg) or "#6c6c6c"
    vim.api.nvim_set_hl(0, "RCodeIgnore", { bg = cbg, fg = col })

    vim.cmd([[
augroup RQmdChunkBg
autocmd ]] .. config.quarto_chunk_hl.events .. [[ <buffer> lua require('r.quarto').hl_code_bg()
augroup END
]])
end

local setup_yaml_hl = function()
    vim.treesitter.query.set(
        "r",
        "highlights",
        [[
; extends
; From quarto.nvim, YAML header for code blocks.
((comment) @comment (#match? @comment "^\\#\\|")) @attribute
; Cell delimiter for Jupyter
((comment) @content (#match? @content "^\\# ?\\%\\%")) @string.special
]]
    )

    vim.treesitter.query.set(
        "python",
        "highlights",
        [[
; extends
; YAML header for code blocks
((comment) @comment (#match? @comment "^\\#\\|")) @attribute
; Cell delimiter for Jupyter
((comment) @content (#match? @content "^\\# ?\\%\\%")) @class.outer @string.special
]]
    )
end

local mtime = function(fname)
    local fd = vim.uv.fs_open(fname, "r", tonumber("644", 8))
    local mt
    if fd then
        mt = vim.uv.fs_fstat(fd).mtime.sec
        vim.uv.fs_close(fd)
    end
    return mt
end

--- Install the "rout" parser, required to properly highlight R output in
--- hover and resolve windows from the language server
local check_rout_parser = function()
    local libext = config.is_windows and "dll" or "so"
    local rout_to = config.rnvim_home .. "/parser/rout." .. libext
    local mt1 = mtime(config.rnvim_home .. "/resources/tree-sitter-rout/grammar.js")
    local mt2 = mtime(rout_to)
    if mt1 and mt2 and mt2 > mt1 then return end

    local rout_from = "libtree-sitter-rout." .. libext
    vim.uv.chdir(config.rnvim_home .. "/resources/tree-sitter-rout")
    vim.system({ "tree-sitter", "generate", "grammar.js" })
    vim.system({ "make" })
    if vim.uv.fs_access(rout_from, "r") then vim.uv.fs_copyfile(rout_from, rout_to) end
end

--- Setup function for initializing module functionality.
-- This includes setting up buffer-specific key mappings, variables, and scheduling additional setup tasks.
M.setup = function()
    local rmdtime = uv.hrtime() -- Track setup time

    check_rout_parser()

    -- Key bindings
    require("r.maps").create(vim.o.filetype)
    -- Only .Rmd and .qmd files use these functions:

    -- Schedule additional setup tasks for PDF viewing and undo functionality
    vim.schedule(function() require("r.pdf").setup() end)

    -- Record setup time for debugging
    rmdtime = (uv.hrtime() - rmdtime) / 1000000000
    require("r.edit").add_to_debug_info("rmd setup", rmdtime, "Time")

    vim.cmd("autocmd BufWritePost <buffer> lua require('r.rmd').update_params()")

    if config.quarto_chunk_hl.highlight == nil then
        config.quarto_chunk_hl.highlight = true
    end
    if config.quarto_chunk_hl.highlight then setup_chunk_hl() end

    if config.quarto_chunk_hl.yaml_hl == nil then
        config.quarto_chunk_hl.yaml_hl = true
    end
    if config.quarto_chunk_hl.yaml_hl then setup_yaml_hl() end
end

--- Compiles the current R Markdown document into a specified output format.
-- This function updates the document before calling the R function `nvim.interlace.rmd`
-- to compile the document, using the specified output format and additional arguments.
---@param outform string The output format for the document compilation (e.g., "html", "pdf").
M.make = function(outform)
    vim.api.nvim_command("update")

    local rmddir = require("r.run").get_buf_dir()
    local rcmd
    if outform == "default" then
        rcmd = 'nvim.interlace.rmd("'
            .. vim.fn.expand("%:t")
            .. '", rmddir = "'
            .. rmddir
            .. '"'
    else
        rcmd = 'nvim.interlace.rmd("'
            .. vim.fn.expand("%:t")
            .. '", outform = "'
            .. outform
            .. '", rmddir = "'
            .. rmddir
            .. '"'
    end

    if config.rmarkdown_args == "" then
        rcmd = rcmd .. ", envir = " .. config.rmd_environment .. ")"
    else
        rcmd = rcmd
            .. ", envir = "
            .. config.rmd_environment
            .. ", "
            .. config.rmarkdown_args:gsub("'", '"')
            .. ")"
    end
    require("r.send").cmd(rcmd)
end

return M
