local warn = require("r").warn
local config = require("r.config").get_config()

local M = {}

M.is_in_R_code = function(vrb)
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{r", "bncW")
    local docline = vim.fn.search("^[ \t]*```$", "bncW")
    if chunkline == vim.fn.line(".") then
        return 2
    elseif chunkline > docline then
        return 1
    else
        if vrb then warn("Not inside an R code chunk.") end
        return 0
    end
end

M.is_in_Py_code = function(vrb)
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{python", "bncW")
    local docline = vim.fn.search("^[ \t]*```$", "bncW")
    if chunkline > docline and chunkline ~= vim.fn.line(".") then
        return 1
    else
        if vrb then warn("Not inside a Python code chunk.") end
        return 0
    end
end

M.write_chunk = function()
    if M.is_in_R_code(0) == 0 then
        if vim.fn.match(vim.fn.getline(vim.fn.line(".")), "^\\s*$") ~= -1 then
            local curline = vim.fn.line(".")
            vim.fn.setline(curline, "```{r}")
            if vim.o.filetype == "quarto" then
                vim.fn.append(curline, { "", "```", "" })
                vim.fn.cursor(curline + 1, 1)
            else
                vim.fn.append(curline, { "```", "" })
                vim.fn.cursor(curline, 5)
            end
            return
        else
            if config.rmdchunk == 2 then
                vim.cmd([[normal! a`r `\<Esc>i]])
                return
            end
        end
    end
    vim.cmd("normal! a`")
end

-- Send Python chunk to R
local send_py_chunk = function(e, m)
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{python", "bncW") + 1
    local docline = vim.fn.search("^[ \t]*```", "ncW") - 1
    local lines = vim.fn.getline(chunkline, docline)
    local ok = vim.fn.RSourceLines(lines, e, "PythonCode")
    if ok == 0 then return end
    if m == "down" then M.RmdNextChunk() end
end

-- Send R chunk to R
M.send_R_chunk = function(e, m)
    if M.is_in_R_code(0) == 2 then vim.fn.cursor(vim.fn.line(".") + 1, 1) end
    if M.is_in_R_code(0) ~= 1 then
        if M.is_in_Py_code(0) == 0 then
            warn("Not inside an R code chunk.")
        else
            send_py_chunk(e, m)
        end
        return
    end
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{r", "bncW") + 1
    local docline = vim.fn.search("^[ \t]*```", "ncW") - 1
    local lines = vim.fn.getline(chunkline, docline)
    local ok = vim.fn.RSourceLines(lines, e, "chunk")
    if ok == 0 then return end
    if m == "down" then vim.fn.RmdNextChunk() end
end

M.previous_chunk = function()
    local curline = vim.fn.line(".")
    if M.is_in_R_code(0) == 1 or M.is_in_Py_code(0) == 1 then
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
            "<Esc>:lua require('r.rmd').write_chunk()<CR>a",
            { silent = true }
        )
    elseif type(cfg.rmdchunk) == "string" then
        vim.api.nvim_buf_set_keymap(
            0,
            "i",
            cfg.rmdchunk,
            "<Esc>:lua require('r.rmd').write_chunk()<CR>a",
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

    -- FIXME: not working:
    if vim.fn.exists("b:undo_ftplugin") == 1 then
        vim.api.nvim_buf_set_var(
            0,
            "undo_ftplugin",
            vim.b.undo_ftplugin .. " | unlet! b:IsInRCode b:rplugin_knitr_pattern"
        )
    else
        vim.api.nvim_buf_set_var(
            0,
            "undo_ftplugin",
            "unlet! b:IsInRCode b:rplugin_knitr_pattern"
        )
    end
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
