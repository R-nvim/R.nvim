local inform = require("r.log").inform
local config = require("r.config").get_config()
local send = require("r.send")
local get_lang = require("r.utils").get_lang
local uv = vim.uv

local M = {}

--- Writes a new R code chunk at the current cursor position
-- This function checks if the cursor is in an empty line and not in an R code chunk
-- it then inserts a new R code chunk template.
-- Different templates are used based on the file type (e.g., Quarto).
M.write_chunk = function()
    local lang = get_lang()
    if lang == "markdown" then
        if vim.api.nvim_get_current_line() == "" then -- Check if cursor is in an empty line
            local curline = vim.api.nvim_win_get_cursor(0)[1]
            -- Insert new R code chunk template
            vim.api.nvim_buf_set_lines(
                0,
                curline - 1,
                curline - 1,
                true,
                { "```{r}", "", "```", "" }
            )
            vim.api.nvim_win_set_cursor(0, { curline + 1, 1 })
            return
        else
            -- inline R code within markdown text
            if config.rmdchunk == "both" then
                local pos = vim.api.nvim_win_get_cursor(0)
                local next_char =
                    vim.api.nvim_get_current_line():sub(pos[2] + 1, pos[2] + 1)
                if next_char == "`" then
                    vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] + 1 })
                elseif vim.fn.col(".") == vim.fn.col("$") then
                    vim.cmd([[normal! a`r `]])
                    vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] + 3 })
                else
                    vim.cmd([[normal! i`r `]])
                    vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] + 3 })
                end
                return
            end
        end
    end

    -- Just insert the backtick
    if vim.fn.col(".") == 1 then
        vim.cmd("normal! i`")
    else
        vim.cmd("normal! a`")
    end
end

-- Internal function to send a Python code chunk to R for execution.
-- This is not exposed in the module table `M` and is only called within `M.send_R_chunk`.
---@param m boolean If true, moves to the next chunk after sending the current one.
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
---@param m boolean If true, moves to the next chunk after sending the current one.
M.send_R_chunk = function(m)
    -- Ensure cursor is at the start of an R code chunk
    if vim.api.nvim_get_current_line():find("^%s*```%s*{r") then
        local lnum = vim.api.nvim_win_get_cursor(0)[1]
        vim.api.nvim_win_set_cursor(0, { lnum + 1, 0 })
    end
    -- Check for R code chunk; if not, check for Python code chunk
    local lang = get_lang()
    if lang ~= "r" then
        if lang ~= "python" then
            inform("Not inside an R code chunk.")
        else
            send_py_chunk(m)
        end
        return
    end
    -- find and send R chunk for execution
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{r", "bncW") + 1
    local docline = vim.fn.search("^[ \t]*```", "ncW") - 1
    local lines = vim.api.nvim_buf_get_lines(0, chunkline - 1, docline, true)
    local ok = send.source_lines(lines, nil)
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
    local cfg = require("r.config").get_config()

    -- Configure key mapping for writing chunks based on configuration settings
    if cfg.rmdchunk == "`" or cfg.rmdchunk == "both" then
        vim.api.nvim_buf_set_keymap(
            0,
            "i",
            "`",
            "<Cmd>lua require('r.rmd').write_chunk()<CR>",
            { silent = true }
        )
    elseif cfg.rmdchunk ~= "" then
        vim.api.nvim_buf_set_keymap(
            0,
            "i",
            tostring(cfg.rmdchunk),
            "<Cmd>lua require('r.rmd').write_chunk()<CR>",
            { silent = true }
        )
    end

    vim.api.nvim_buf_set_var(0, "rplugin_knitr_pattern", "^``` *{.*}$")

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
