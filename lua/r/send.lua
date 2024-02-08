-- TODO: Make the echo/silent option work

local config = require("r.config").get_config()
local warn = require("r").warn
local cursor = require("r.cursor")
local paragraph = require("r.paragraph")
local all_marks = "abcdefghijklmnopqrstuvwxyz"
-- FIXME: convert to Lua pattern
local op_pattern = [[\(&\||\|+\|-\|\*\|/\|=\|\~\|%\|->\||>\)\s*$']]

local paren_diff = function(str)
    local clnln = str
    -- FIXME: delete strings before calculating the diff because the line
    -- may have unbalanced parentheses within a string.
    -- clnln = string.gsub(clnln, '"', "")
    -- clnln = string.gsub(clnln, "'", "")
    -- clnln = string.gsub(clnln, '".-"', "")
    -- clnln = string.gsub(clnln, "'.-'", "")
    clnln = clnln:gsub("#.*", "")
    local llen1 = string.len(string.gsub(clnln, "[%{%(%[]", ""))
    local llen2 = string.len(string.gsub(clnln, "[%}%)%]]", ""))
    return llen1 - llen2
end

local M = {}

M.set_send_cmd_fun = function()
    if config.RStudio_cmd then
        M.cmd = require("r.rstudio").send_cmd_to_RStudio
    elseif type(config.external_term) == "boolean" and config.external_term == false then
        M.cmd = require("r.term").send_cmd_to_term
    elseif config.is_windows then
        M.cmd = require("r.windows").send_cmd_to_Rgui
    elseif config.is_darwin and config.applescript then
        M.cmd = require("r.osx").send_cmd_to_Rapp
    else
        M.cmd = require("r.external_term").send_cmd_to_external_term
    end
    vim.g.R_Nvim_status = 7
end

M.not_ready = function(_) warn("R is not ready yet.") end

--- Send a string to R Console.
---@param _ string The line to be sent.
M.not_running = function(_) warn("Did you start R?") end

M.cmd = M.not_running

M.get_source_args = function(e)
    -- local sargs = config.source_args or ''
    local sargs = ""
    if config.source_args ~= "" then sargs = ", " .. config.source_args end

    if e == "echo" then sargs = sargs .. ", echo=TRUE" end
    return sargs
end

M.source_lines = function(lines, verbose, what)
    require("r.edit").add_for_deletion(config.source_write)

    if vim.o.filetype == "rmd" or vim.o.filetype == "quarto" then
        lines =
            vim.fn.map(vim.deepcopy(lines), 'substitute(v:val, "^\\(``\\)\\?", "", "")')
    end

    if what and what == "NewtabInsert" then
        vim.fn.writefile(lines, config.source_write)
        require("r.run").send_to_nvimcom(
            "E",
            'nvimcom:::nvim_capture_source_output("'
                .. config.source_read
                .. '", "NewtabInsert")'
        )
        return 1
    end

    local rcmd

    -- The "bracketed paste" option is not documented because it is not well
    -- tested and source() have always worked flawlessly.
    -- FIXME: document it
    if config.source_args == "bracketed paste" then
        rcmd = "\033[200~" .. table.concat(lines, "\n") .. "\033[201~"
    else
        vim.fn.writefile(lines, config.source_write)
        local sargs = string.gsub(M.get_source_args(verbose), "^, ", "")
        if what then
            rcmd = "NvimR." .. what .. "(" .. sargs .. ")"
        else
            rcmd = "NvimR.source(" .. sargs .. ")"
        end
    end

    if what and what == "PythonCode" then
        rcmd = 'reticulate::py_run_file("' .. config.source_read .. '")'
    end

    local ok = M.cmd(rcmd)
    return ok
end

M.above_lines = function()
    local lines = vim.api.nvim_buf_get_lines(0, 1, vim.fn.line(".") - 1, false)

    -- Remove empty lines from the end of the list
    local result =
        table.concat(vim.tbl_filter(function(line) return line ~= "" end, lines), "\n")

    M.cmd(result)
end

M.source_file = function(e)
    local bufnr = 0
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    M.cmd(lines)
end

-- Send the current paragraph to R. If m == 'down', move the cursor to the
-- first line of the next paragraph.
M.paragraph = function(e, m)
    local start_line, end_line = paragraph.get_current()

    local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line, false)
    M.cmd(table.concat(lines, "\n"))

    if m == "down" then cursor.move_next_paragraph() end
end

M.line_part = function(direction, correctpos)
    local lin = vim.api.nvim_buf_get_lines(0, vim.fn.line("."), vim.fn.line("."), true)[1]
    local idx = vim.fn.col(".") - 1
    if correctpos then vim.fn.cursor(vim.fn.line("."), idx) end
    local rcmd
    if direction == "right" then
        rcmd = string.sub(lin, idx + 1)
    else
        rcmd = string.sub(lin, 1, idx + 1)
    end
    M.cmd(rcmd)
end

-- Send the current function
M.fun = function()
    warn(
        "Sending function not implemented. It will be either implemented using treesitter or never implemented."
    )
end

local knit_child = function(line, godown)
    local nline = vim.fn.substitute(line, ".*child *= *", "", "")
    local cfile = vim.fn.substitute(nline, nline:sub(1, 1), "", "")
    cfile = vim.fn.substitute(cfile, nline:sub(1, 1) .. ".*", "", "")
    if vim.fn.filereadable(cfile) == 1 then
        local ok =
            vim.fn["g:M.cmd"]("require(knitr); knit('" .. cfile .. "', output=NULL)")
        if godown:find("down") then
            vim.api.nvim_win_set_cursor(0, { vim.fn.line(".") + 1, 1 })
            vim.cmd("call cursor.move_next_line()")
        end
    else
        warn("File not found: '" .. cfile .. "'")
    end
end

M.chunks_up_to_here = function()
    local filetype = vim.o.filetype
    local codelines = {}
    local here = vim.fn.line(".")
    local curbuf = vim.fn.getline(1, "$")
    local idx = 0

    while idx < here do
        local begchk, endchk, chdchk

        if filetype == "rnoweb" then
            begchk = "^<<.*>>=\\$"
            endchk = "^@"
            chdchk = "^<<.*child *= *"
        elseif filetype == "rmd" or filetype == "quarto" then
            begchk = "^[ \t]*```[ ]*{r"
            endchk = "^[ \t]*```$"
            chdchk = "^```.*child *= *"
        else
            -- Should never happen
            warn('Strange filetype (SendFHChunkToR): "' .. filetype .. '"')
            return
        end

        if
            curbuf[idx + 1]:match(begchk)
            and not curbuf[idx + 1]:match("\\<eval\\s*=\\s*F")
        then
            -- Child R chunk
            if curbuf[idx + 1]:match(chdchk) then
                -- First, run everything up to the child chunk and reset buffer
                vim.fn["M.source_lines"](codelines, "silent", "chunk")
                codelines = {}

                -- Next, run the child chunk and continue
                knit_child(curbuf[idx + 1], "stay")
                idx = idx + 1
            else
                idx = idx + 1
                while not curbuf[idx + 1]:match(endchk) and idx < here do
                    table.insert(codelines, curbuf[idx + 1])
                    idx = idx + 1
                end
            end
        else
            idx = idx + 1
        end
    end

    vim.fn["M.source_lines"](codelines, "silent", "chunk")
end

-- Send motion to R
M.motion = function(type)
    local lstart = vim.fn.line("'[")
    local lend = vim.fn.line("']")
    if lstart == lend then
        M.line("stay", lstart)
    else
        local lines = vim.fn["getline"](lstart, lend)
        vim.fn.M.source_lines(lines, "", "block")
    end
end

-- Send block to R (Adapted from marksbrowser plugin)
-- Function to get the marks which the cursor is between
M.marked_block = function(e, m)
    if vim.o.filetype ~= "r" and vim.fn["IsInRCode"](1) ~= 1 then return end

    local curline = vim.fn.line(".")
    local lineA = 1
    local lineB = vim.fn.line("$")
    local maxmarks = string.len(all_marks)
    local n = 0

    while n < maxmarks do
        local c = string.sub(all_marks, n + 1, n + 1)
        local lnum = vim.fn.line("'" .. c)

        if lnum ~= 0 then
            if lnum <= curline and lnum > lineA then
                lineA = lnum
            elseif lnum > curline and lnum < lineB then
                lineB = lnum
            end
        end

        n = n + 1
    end

    if lineA == 1 and lineB == vim.fn.line("$") then
        warn("The file has no mark!")
        return
    end

    if lineB < vim.fn.line("$") then lineB = lineB - 1 end

    local lines = vim.fn["getline"](lineA, lineB)
    local ok = vim.fn.M.source_lines(lines, e, "block")

    if ok == 0 then return end

    if m == "down" and lineB ~= vim.fn.line("$") then
        vim.fn.cursor(lineB, 1)
        vim.fn.cursor.move_next_line()
    end
end

M.selection = function()
    local ispy = 0

    if vim.o.filetype ~= "r" then
        if
            (vim.o.filetype == "rmd" or vim.o.filetype == "quarto")
            and require("r.rmd").is_in_Py_code(0)
        then
            ispy = 1
        elseif vim.b.IsInRCode(0) ~= 1 then
            if
                (
                    vim.o.filetype == "rnoweb"
                    and vim.fn.getline(vim.fn.line(".")) ~= "\\Sexpr{"
                )
                or (
                    (vim.o.filetype == "rmd" or vim.o.filetype == "quarto")
                    and vim.fn.getline(vim.fn.line(".")) ~= "`r "
                )
            then
                warn("Not inside an R code chunk.")
                return
            end
        end
    end

    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")

    if start_line == end_line then
        local i = vim.fn.col("'<") - 1
        local j = vim.fn.col("'>") - i
        local l = vim.fn.getline(vim.fn.line("'<"))
        local line = string.sub(l, i, i + j)
        if vim.o.filetype == "r" then line = cursor.clean_oxygen_line(line) end
        local ok = M.cmd(line)
        if ok and vim.fn.a[2] == "down" then cursor.move_next_line() end
        return
    end

    local lines =
        vim.api.nvim_buf_get_lines(0, vim.fn.line("'<"), vim.fn.line("'>"), true)
    if vim.visualmode() == "\\<C-V>" then
        local lj = vim.fn.line("'<")
        local cj = vim.fn.col("'<")
        local lk = vim.fn.line("'>")
        local ck = vim.fn.col("'>")
        local bb, ee
        if cj > ck then
            bb = ck - 1
            ee = cj - ck + 1
        else
            bb = cj - 1
            ee = ck - cj + 1
        end
        local cutlines = {}
        for k, v in pairs(lines) do
            table.insert(cutlines, v:sub(cj, ck))
        end
        lines = cutlines
    else
        local i = vim.fn.col("'<") - 1
        local j = vim.fn.col("'>")
        lines[1] = string.sub(lines[1], i)
        local llen = #lines
        lines[llen] = string.sub(lines[llen], 0, j - 1)
    end

    local curpos = vim.fn.getpos(".")
    local curline = vim.fn.line("'<")
    for idx, line in ipairs(lines) do
        vim.fn.setpos(".", { 0, curline, 1, 0 })
        if vim.o.filetype == "r" then lines[idx] = cursor.clean_oxygen_line(line) end
        curline = curline + 1
    end
    vim.fn.setpos(".", curpos)

    local ok
    if vim.fn.a[0] == 3 and vim.fn.a[3] == "NewtabInsert" then
        ok = M.source_lines(lines, vim.fn.a[1], "NewtabInsert")
    elseif ispy then
        ok = M.source_lines(lines, vim.fn.a[1], "PythonCode")
    else
        ok = M.source_lines(lines, vim.fn.a[1], "selection")
    end

    if ok == 0 then return end

    if vim.fn.a[2] == "down" then
        cursor.move_next_line()
    else
        if vim.fn.a[0] < 3 or (vim.fn.a[0] == 3 and vim.fn.a[3] ~= "normal") then
            vim.cmd("normal! gv")
        end
    end
end

--- Send current line to R Console
---@param move string Movement to do after sending the line.
---@param lnum number Number of line to send (optional).
M.line = function(move, lnum)
    if not lnum then lnum = vim.fn.line(".") end
    local line = vim.fn.getline(lnum)
    if #line == 0 then
        if move == "down" then cursor.move_next_line() end
        return
    end

    if vim.o.filetype == "rnoweb" then
        if line == "@" then
            if move == "down" then cursor.move_next_line() end
            return
        end
        if line:find("^<<.*child *= *") then
            knit_child(lnum, move)
            return
        end
        if not require("r.rnw").is_in_R_code(true) then return end
    end

    if vim.o.filetype == "rmd" or vim.o.filetype == "quarto" then
        if line == "```" then
            if move == "down" then cursor.move_next_line() end
            return
        end
        if vim.fn.match(line, "^```.*child *= *") > -1 then
            knit_child(lnum, move)
            return
        end
        line = vim.fn.substitute(line, "^(\\`\\`)\\?", "", "")
        if not require("r.rmd").is_in_R_code(false) then
            if not require("r.rmd").is_in_Py_code(false) then
                warn("Not inside either R or Python code chunk.")
            else
                line = 'reticulate::py_run_string("'
                    .. vim.fn.substitute(line, '"', '\\"', "g")
                    .. '")'
            end
            return
        end
    end

    -- FIXME: filetype rdoc no longer exists
    if vim.o.filetype == "rdoc" then
        local line1 = vim.fn.getline(vim.fn.line("."))
        if line1:find("^The topic") then
            local topic = vim.fn.substitute(line, ".*::", "", "")
            local package = vim.fn.substitute(line, "::.*", "", "")
            require("r.rdoc").ask_R_doc(topic, package, true)
            return
        end
        if not require("r.rdoc").is_in_R_code(true) then return end
    end

    if vim.o.filetype == "rhelp" and not require("r.rhelp").is_in_R_code(true) then
        return
    end

    if vim.o.filetype == "r" then line = cursor.clean_oxygen_line(line) end

    -- FIXME: Send the whole block within curly braces
    local has_block = false
    local has_op = false
    if config.parenblock then
        local chunkend = nil
        if vim.o.filetype == "rmd" or vim.o.filetype == "quarto" then
            chunkend = "```"
        elseif vim.o.filetype == "rnoweb" then
            chunkend = "@"
        end
        local rpd = paren_diff(line)
        has_op = line:gsub("#.*", ""):find(op_pattern) and true or false
        if rpd < 0 then
            local line1 = lnum
            local cline = line1 + 1
            local last_buf_line = vim.fn.line("$")
            local lines = { line }
            while cline <= last_buf_line do
                local txt = vim.fn.getline(cline)
                if chunkend and txt == chunkend then break end
                table.insert(lines, txt)
                rpd = rpd + paren_diff(txt)
                if rpd == 0 then
                    has_op = vim.fn.getline(cline):gsub("#.*", ""):find(op_pattern)
                            and true
                        or false
                    vim.fn.cursor(cline, 1)
                    has_block = true
                    break
                end
                cline = cline + 1
            end
            if has_block then line = table.concat(lines, "\n") end
        end
    end

    if config.bracketed_paste then
        M.cmd("\033[200~" .. line .. "\033[201~\n", 0)
    else
        M.cmd(line)
    end

    if move == "down" then
        cursor.move_next_line()
        -- Send the whole chain of piped lines
        if has_op then M.line(move, lnum) end
    elseif move == "newline" then
        vim.cmd("normal! o")
    end
end

return M
