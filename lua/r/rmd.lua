local warn = require("r").warn
local config = require("r.config").get_config()
local send = require("r.send")

local M = {}

--- Checks if the cursor is currently positioned inside a R code block within a document.
-- This function searches backwards for the start of an R code chunk indicated by ```{r
-- and forwards for the end of any code chunk indicated by ```. It then compares these positions
-- to determine if the cursor is inside a R code block.
---@param vrb boolean If true, it will display a warning message when the cursor is not inside an R code chunk.
---@return boolean Returns true if inside an R code chunk, false otherwise.
M.is_in_R_code = function(vrb)
    -- bncW: search backwards, don't move cursor, also match at cursor, no wrap around the end of the buffer
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{r", "bncW") -- Search for R chunk start
    local docline = vim.fn.search("^[ \t]*```$", "bncW") -- Search for any code chunk end (buggy??)
    if chunkline > docline and chunkline ~= vim.fn.line(".") then
        return true
    else
        if vrb then warn("Not inside an R code chunk.") end
        return false
    end
end

--- Checks if the cursor is currently positioned inside a Python code block within a document.
-- Similar to `is_in_R_code` but checks for Python code blocks instead.
-- @param vrb boolean If true, displays a warning when not inside a Python code chunk.
-- @return boolean True if inside a Python code chunk, false otherwise.
M.is_in_Py_code = function(vrb)
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{python", "bncW")
    local docline = vim.fn.search("^[ \t]*```$", "bncW")
    if chunkline > docline and chunkline ~= vim.fn.line(".") then
        return true
    else
        if vrb then warn("Not inside a Python code chunk.") end
        return false
    end
end

M.write_chunk = function()
    if not M.is_in_R_code(false) then
        if vim.fn.getline(vim.fn.line(".")):find("^%s*$") then
            local curline = vim.fn.line(".")
            if vim.o.filetype == "quarto" then
                vim.api.nvim_buf_set_lines(
                    0,
                    curline - 1,
                    curline - 1,
                    true,
                    { "```{r}", "", "```", "" }
                )
                vim.api.nvim_win_set_cursor(0, { curline + 1, 1 })
            else
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
    if vim.fn.col(".") == 1 then
        vim.cmd("normal! i`")
    else
        vim.cmd("normal! a`")
    end
end

-- Send Python chunk to R
local send_py_chunk = function(m)
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{python", "bncW") + 1
    local docline = vim.fn.search("^[ \t]*```", "ncW") - 1
    local lines = vim.api.nvim_buf_get_lines(0, chunkline - 1, docline, true)
    local ok = send.source_lines(lines, "PythonCode")
    if ok == 0 then return end
    if m == true then M.next_chunk() end
end

-- Send R chunk to R
M.send_R_chunk = function(m)
    if vim.fn.getline(vim.fn.line(".")):find("^%s*```%s*{r") then
        vim.fn.cursor(vim.fn.line(".") + 1, 1)
    end
    if not M.is_in_R_code(false) then
        if not M.is_in_Py_code(false) then
            warn("Not inside an R code chunk.")
        else
            send_py_chunk(m)
        end
        return
    end
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{r", "bncW") + 1
    local docline = vim.fn.search("^[ \t]*```", "ncW") - 1
    local lines = vim.api.nvim_buf_get_lines(0, chunkline - 1, docline, true)
    local ok = send.source_lines(lines, m)
    if ok == 0 then return end
    if m == true then M.next_chunk() end
end

M.previous_chunk = function()
    local curline = vim.fn.line(".")
    if M.is_in_R_code(false) or M.is_in_Py_code(false) then
        local i = vim.fn.search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW")
        if i ~= 0 then vim.fn.cursor(i - 1, 1) end
    end
    local i = vim.fn.search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW")
    if i == 0 then
        vim.fn.cursor(curline, 1)
        warn("There is no previous R code chunk to go.")
        return
    else
        vim.fn.cursor(i + 1, 1)
    end
end

M.next_chunk = function()
    local i = vim.fn.search("^[ \t]*```[ ]*{\\(r\\|python\\)", "nW")
    if i == 0 then
        warn("There is no next R code chunk to go.")
        return
    else
        vim.fn.cursor(i + 1, 1)
    end
end

M.setup = function()
    local rmdtime = vim.fn.reltime()
    local cfg = require("r.config").get_config()

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
    vim.api.nvim_buf_set_var(0, "IsInRCode", M.is_in_R_code)

    -- Key bindings
    require("r.maps").create(vim.o.filetype)
    -- Only .Rmd and .qmd files use these functions:

    vim.schedule(function() require("r.pdf").setup() end)

    vim.schedule(function()
        if vim.b.undo_ftplugin then
            vim.b.undo_ftplugin = vim.b.undo_ftplugin
                .. " | unlet! b:IsInRCode b:rplugin_knitr_pattern"
        else
            vim.b.undo_ftplugin = "unlet! b:IsInRCode b:rplugin_knitr_pattern"
        end
    end)
    require("r.edit").add_to_debug_info(
        "rmd setup",
        vim.fn.reltimefloat(vim.fn.reltime(rmdtime, vim.fn.reltime())),
        "Time"
    )
end

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
