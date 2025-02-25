local inform = require("r.log").inform
local config = require("r.config").get_config()
local get_lang = require("r.utils").get_lang
local uv = vim.uv
local chunk_key = nil
local quarto = require("r.quarto")
local source_chunk = require("r.send").source_chunk

local M = {}

--- Writes a new R code chunk at the current cursor position
M.write_chunk = function()
    local curpos = vim.api.nvim_win_get_cursor(0)
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
    chunks = quarto.filter_code_chunks_by_eval(chunks)
    chunks = quarto.filter_code_chunks_by_lang(chunks, { "r", "python" })

    if #chunks == 0 then
        inform("No R or Python code chunk found at the cursor position.")
        return
    end

    local codelines = quarto.codelines_from_chunks(chunks)

    local lines = table.concat(codelines, "\n")

    local ok = source_chunk(lines)
    if ok == 0 then return end
    if m == true then M.next_chunk() end
end

--- Navigates to the previous R or Python code chunk in the document.
-- This function searches backwards from the current cursor position for the start of
-- any R or Python code chunk.
---@return boolean
local go_to_previous = function()
    local curline = vim.api.nvim_win_get_cursor(0)[1]
    local lang = get_lang()
    if lang == "r" or lang == "python" then
        local i = vim.fn.search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW") -- search for chunk start
        if i ~= 0 then vim.api.nvim_win_set_cursor(0, { i - 1, 0 }) end -- if found, move cursor at chunk
    end
    local i = vim.fn.search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW") -- Search again for chunk start
    if i == 0 then
        vim.api.nvim_win_set_cursor(0, { curline, 0 })
        inform("There is no previous R code chunk to go.")
        return false
    end
    vim.api.nvim_win_set_cursor(0, { i + 1, 0 }) -- position cursor inside the chunk
    return true
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
    local i = vim.fn.search("^[ \t]*```[ ]*{\\(r\\|python\\)", "nW") -- Search for the next chunk start
    if i == 0 then
        inform("There is no next R code chunk to go.")
        return false
    end
    vim.api.nvim_win_set_cursor(0, { i + 1, 0 }) -- position cursor inside the next chunk
    return true
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

--- Setup function for initializing module functionality.
-- This includes setting up buffer-specific key mappings, variables, and scheduling additional setup tasks.
M.setup = function()
    local rmdtime = uv.hrtime() -- Track setup time

    -- Key bindings
    require("r.maps").create(vim.o.filetype)
    -- Only .Rmd and .qmd files use these functions:

    -- Schedule additional setup tasks for PDF viewing and undo functionality
    vim.schedule(function() require("r.pdf").setup() end)

    -- Record setup time for debugging
    rmdtime = (uv.hrtime() - rmdtime) / 1000000000
    require("r.edit").add_to_debug_info("rmd setup", rmdtime, "Time")
    vim.cmd("autocmd BufWritePost <buffer> lua require('r.rmd').update_params()")
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
