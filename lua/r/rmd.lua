
local M = {}

M.is_in_R_code = function (vrb)
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{r", "bncW")
    local docline = vim.fn.search("^[ \t]*```$", "bncW")
    if chunkline == vim.fn.line(".") then
        return 2
    elseif chunkline > docline then
        return 1
    else
        if vrb then
            vim.notify("Not inside an R code chunk.", vim.log.levels.WARN)
        end
        return 0
    end
end

M.is_in_Py_code = function (vrb)
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{python", "bncW")
    local docline = vim.fn.search("^[ \t]*```$", "bncW")
    if chunkline > docline and chunkline ~= vim.fn.line(".") then
        return 1
    else
        if vrb then
            vim.notify("Not inside a Python code chunk.", vim.log.levels.WARN)
        end
        return 0
    end
end

M.write_chunk = function ()
    if M.is_in_R_code(0) == 0 then
        if vim.fn.match(vim.fn.getline(vim.fn.line(".")), "^\\s*$") ~= -1 then
            local curline = vim.fn.line(".")
            vim.fn.setline(curline, "```{r}")
            if vim.bo.filetype == 'quarto' then
                vim.fn.append(curline, {"", "```", ""})
                vim.fn.cursor(curline + 1, 1)
            else
                vim.fn.append(curline, {"```", ""})
                vim.fn.cursor(curline, 5)
            end
            return
        else
            if vim.g.Rcfg.rmdchunk == 2 then
                vim.cmd([[normal! a`r `\<Esc>i]])
                return
            end
        end
    end
    vim.cmd('normal! a`')
end


-- Send Python chunk to R
local send_py_chunk = function (e, m)
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{python", "bncW") + 1
    local docline = vim.fn.search("^[ \t]*```", "ncW") - 1
    local lines = vim.fn.getline(chunkline, docline)
    local ok = vim.fn.RSourceLines(lines, e, 'PythonCode')
    if ok == 0 then
        return
    end
    if m == "down" then
        M.RmdNextChunk()
    end
end

-- Send R chunk to R
M.send_R_chunk = function (e, m)
    if M.is_in_R_code(0) == 2 then
        vim.fn.cursor(vim.fn.line(".") + 1, 1)
    end
    if M.is_in_R_code(0) ~= 1 then
        if M.is_in_Py_code(0) == 0 then
            vim.notify("Not inside an R code chunk.", vim.log.levels.WARN)
        else
            send_py_chunk(e, m)
        end
        return
    end
    local chunkline = vim.fn.search("^[ \t]*```[ ]*{r", "bncW") + 1
    local docline = vim.fn.search("^[ \t]*```", "ncW") - 1
    local lines = vim.fn.getline(chunkline, docline)
    local ok = vim.fn.RSourceLines(lines, e, "chunk")
    if ok == 0 then
        return
    end
    if m == "down" then
        vim.fn.RmdNextChunk()
    end
end

M.previous_chunk = function ()
    local curline = vim.fn.line(".")
    if M.is_in_R_code(0) == 1 or M.is_in_Py_code(0) == 1 then
        local i = vim.fn.search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW")
        if i ~= 0 then
            vim.fn.cursor(i-1, 1)
        end
    end
    local i = vim.fn.search("^[ \t]*```[ ]*{\\(r\\|python\\)", "bnW")
    if i == 0 then
        vim.fn.cursor(curline, 1)
        vim.notify("There is no previous R code chunk to go.", vim.log.levels.WARN)
        return
    else
        vim.fn.cursor(i+1, 1)
    end
end

M.next_chunk = function ()
    local i = vim.fn.search("^[ \t]*```[ ]*{\\(r\\|python\\)", "nW")
    if i == 0 then
        vim.notify("There is no next R code chunk to go.", vim.log.levels.WARN)
        return
    else
        vim.fn.cursor(i+1, 1)
    end
end

return M
