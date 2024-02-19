local warn = require("r").warn
local config = require("r.config").get_config()
local send = require("r.send")

local M = {}


--- Checks if the cursor is currently positioned inside a code block within a document for a specified language.
-- This function searches backwards for the start of a code chunk indicated by ```{language
-- and forwards for the end of any code chunk indicated by ```. It then compares these positions
-- to determine if the cursor is inside a code block of the specified language.
-- @param language string The programming language to check for (e.g., 'r', 'python').
-- @param verbose boolean If true, it will display a warning message when the cursor is not inside a code chunk of the specified language.
-- @return boolean Returns true if inside a code chunk of the specified language, false otherwise.
M.is_in_code_chunk = function(language, verbose)
    local chunkStartPattern = "^[ \t]*```[ ]*{" .. language
    -- bncW: search backwards, don't move cursor, also match at cursor, no wrap around the end of the buffer
    local chunkline = vim.fn.search(chunkStartPattern, "bncW") -- Search for chunk start
    local docline = vim.fn.search("^[ \t]*```$", "bncW") -- Search for any code chunk end
    if chunkline > docline and chunkline ~= vim.fn.line(".") then
        return true
    else
        if verbose then warn("Not inside a " .. language .. " code chunk.") end -- Warn if not in chunk and verbose is true
        return false
    end
end

--- Checks if the cursor is currently positioned inside a R code block within a document.
-- This function is now a wrapper around the generalized `is_in_code_chunk` function.
---@param vrb boolean If true, it will display a warning message when the cursor is not inside an R code chunk.
---@return boolean Returns true if inside an R code chunk, false otherwise.
M.is_in_R_code = function(vrb)
    return M.is_in_code_chunk("r", vrb)
end


--- Writes a new R code chunk at the current cursor position
-- This function checks if the cursor is in an empty line and not in an R code chunk
-- it then inserts a new R code chunk template.
-- Different templates are used based on the file type (e.g., Quarto).
M.write_chunk = function()
    if not M.is_in_code_chunk('r', false) then -- Check if cursor is inside an R code chunk
        if vim.fn.getline(vim.fn.line(".")):find("^%s*$") then  -- Check if cursor is in an empty line
            local curline = vim.fn.line(".")
            -- Insert new R code chunk template based on filetype
            if vim.o.filetype == "quarto" then -- Quarto
                vim.api.nvim_buf_set_lines(
                    0,
                    curline - 1,
                    curline - 1,
                    true,
                    { "```{r}", "", "```", "" }
                )
                vim.api.nvim_win_set_cursor(0, { curline + 1, 1 })
            else -- not Quarto (R Markdown)
                vim.api.nvim_buf_set_lines(
                    0,
                    curline - 1,
                    curline - 1,
                    true,
                    { "```{r}", "```", "" }
                )
                vim.api.nvim_win_set_cursor(0, { curline, 5 })
            end
            return
        else
            -- TODO: Document this part
            if config.rmdchunk == 2 then
                if vim.fn.col(".") == 1 then
                    vim.cmd([[normal! i`r `]])
                else
                    vim.cmd([[normal! a`r `]])
                end
                vim.api.nvim_win_set_cursor(0, { vim.fn.line("."), vim.fn.col(".") - 1 })
                return
            end
        end
    end
    -- TODO: Document this part
    if vim.fn.col(".") == 1 then
        vim.cmd("normal! i`")
    else
        vim.cmd("normal! a`")
    end
end

-- Internal function to send a Python code chunk to R for execution.
-- This is not exposed in the module table `M` and is only called within `M.send_R_chunk`.
-- @param m boolean If true, moves to the next chunk after sending the current one.
local send_py_chunk = function(m)
    -- Find the start and end of Python code chunk
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{python", "bncW") + 1
    local docline = vim.fn.search("^[ \t]*```", "ncW") - 1
    local lines = vim.api.nvim_buf_get_lines(0, chunkline - 1, docline, true) -- Get chunk lines
    local ok = send.source_lines(lines, "PythonCode")
    if ok == 0 then return end -- check if sending was successful
    if m == true then M.next_chunk() end -- optional: move to next chunk
end

--- Sends the current R code chunk to R for execution.
-- This function ensures the cursor is positioned inside an R code chunk before attempting to send it.
-- If inside a Python code chunk, it will delegate to `send_py_chunk`.
-- @param m boolean If true, moves to the next chunk after sending the current one.
M.send_R_chunk = function(m)
    -- Ensure cursor is at the start of an R code chunk
    if vim.fn.getline(vim.fn.line(".")):find("^%s*```%s*{r") then
        vim.fn.cursor(vim.fn.line(".") + 1, 1)
    end
    -- Check for R code chunk; if not, check for Python code chunk
    if not M.is_in_code_chunk('r', false) then
        if not M.is_in_code_chunk('python', false) then
            warn("Not inside an R code chunk.")
        else
            send_py_chunk(m)
        end
        return
    end
    -- find and send R chunk for execution
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{r", "bncW") + 1
    local docline = vim.fn.search("^[ \t]*```", "ncW") - 1
    local lines = vim.api.nvim_buf_get_lines(0, chunkline - 1, docline, true)
    local ok = send.source_lines(lines, m)
    if ok == 0 then return end
    if m == true then M.next_chunk() end
end

--- Navigates to the previous R or Python code chunk in the document.
-- This function searches backwards from the current cursor position for the start of
-- any R or Python code chunk.
M.previous_chunk = function()
    local curline = vim.fn.line(".")
    if M.is_in_code_chunk('r', false) or M.is_in_code_chunk('python', false) then
        local i = vim.fn.search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW") -- search for chunk start
        if i ~= 0 then vim.fn.cursor(i - 1, 1) end -- if found, move cursor at chunk
    end
    local i = vim.fn.search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW") -- Search again for chunk start
    if i == 0 then
        vim.fn.cursor(curline, 1)
        warn("There is no previous R code chunk to go.")
        return
    else
        vim.fn.cursor(i + 1, 1) -- position cursor inside the chunk
    end
end

--- Navigates to the next R or Python code chunk in the document.
-- This function searches forward from the current cursor position for the start of any R or Python code chunk.
M.next_chunk = function()
    local i = vim.fn.search("^[ \t]*```[ ]*{\\(r\\|python\\)", "nW") -- Search for the next chunk start
    if i == 0 then
        warn("There is no next R code chunk to go.")
        return
    else
        vim.fn.cursor(i + 1, 1) -- position cursor inside the next chunk
    end
end

--- Setup function for initializing module functionality.
-- This includes setting up buffer-specific key mappings, variables, and scheduling additional setup tasks.
M.setup = function()
    local rmdtime = vim.fn.reltime() -- Track setup time
    local cfg = require("r.config").get_config()

    -- Configure key mapping for writing chunks based on configuration settings (TODO: elaborate)
    if type(cfg.rmdchunk) == "number" and (cfg.rmdchunk == 1 or cfg.rmdchunk == 2) then
        vim.api.nvim_buf_set_keymap(
            0,
            "i",
            "`",
            "<Cmd>lua require('r.rmd').write_chunk()<CR>",
            { silent = true }
        )
    elseif type(cfg.rmdchunk) == "string" then
        vim.api.nvim_buf_set_keymap(
            0,
            "i",
            cfg.rmdchunk,
            "<Cmd>lua require('r.rmd').write_chunk()<CR>",
            { silent = true }
        )
    end

    vim.api.nvim_buf_set_var(0, "rplugin_knitr_pattern", "^``` *{.*}$")

    -- Pointer to function called by generic functions
    -- TODO: replace with M.is_in_code_chunk then remove is_in_R_code definition
    vim.api.nvim_buf_set_var(0, "IsInRCode", M.is_in_R_code)

    -- Key bindings
    require("r.maps").create(vim.o.filetype)
    -- Only .Rmd and .qmd files use these functions:

    -- Schedule additional setup tasks for PDF viewing and undo functionality
    vim.schedule(function() require("r.pdf").setup() end)

    vim.schedule(function()
        if vim.b.undo_ftplugin then
            vim.b.undo_ftplugin = vim.b.undo_ftplugin
                .. " | unlet! b:IsInRCode b:rplugin_knitr_pattern"
        else
            vim.b.undo_ftplugin = "unlet! b:IsInRCode b:rplugin_knitr_pattern"
        end
    end)
    -- Record setup time for debugging
    require("r.edit").add_to_debug_info(
        "rmd setup",
        vim.fn.reltimefloat(vim.fn.reltime(rmdtime, vim.fn.reltime())),
        "Time"
    )
end

--TODO: Explain the insides of M.make

--- Compiles the current R Markdown document into a specified output format.
-- This function updates the document before calling the R function `nvim.interlace.rmd`
-- to compile the document, using the specified output format and additional arguments.
-- @param outform string The output format for the document compilation (e.g., "html", "pdf").
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
