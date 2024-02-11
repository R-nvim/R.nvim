-- TODO: Make the echo/silent option work

local config = require("r.config").get_config()
local warn = require("r").warn
local utils = require("r.utils")
local edit = require("r.edit")
local cursor = require("r.cursor")
local paragraph = require("r.paragraph")
local all_marks = "abcdefghijklmnopqrstuvwxyz"

--- Check if line ends with operator symbol
---@param line string
---@return boolean
local ends_with_operator = function(line)
    local op_pattern = { "&", "|", "+", "-", "%*", "%/", "%=", "~", "%-", "%<", "%>" }
    local clnline = line:gsub("#.*", "")
    local has_op = false
    for _, v in pairs(op_pattern) do
        if clnline:find(v .. "%s*$") then
            has_op = true
            break
        end
    end
    return has_op
end

--- Check if the number of brackets are balanced
---@param str string The line to check
---@return number
local paren_diff = function(str)
    local clnln = str
    clnln = clnln:gsub('\\"', "")
    clnln = clnln:gsub("\\'", "")
    clnln = clnln:gsub('".-"', "")
    clnln = clnln:gsub("'.-'", "")
    clnln = clnln:gsub("#.*", "")
    local llen1 = string.len(clnln:gsub("[%{%(%[]", ""))
    local llen2 = string.len(clnln:gsub("[%}%)%]]", ""))
    return llen1 - llen2
end

local M = {}

--- Change the pointer to the function used to send commands to R.
M.set_send_cmd_fun = function()
    if vim.g.R_Nvim_status < 4 then
        M.cmd = M.not_running
        return
    end

    if vim.g.R_Nvim_status < 7 then
        M.cmd = M.not_ready
        return
    end

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
end

--- Warns that R is not ready to receive commands yet.
---@param _ string The command that will not be sent to anywhere.
---@return boolean
M.not_ready = function(_)
    warn("R is not ready yet.")
    return false
end

--- Warns that R is not running.
---@param _ string The command that will not be sent to anywhere.
---@return boolean
M.not_running = function(_)
    warn("Did you start R?")
    return false
end

M.cmd = M.not_running

--- Add a comma to the beginning of arguments to be passed to base::source().
---@return string
M.get_source_args = function()
    -- local sargs = config.source_args or ''
    local sargs = ""
    if config.source_args ~= "" then sargs = ", " .. config.source_args end
    return sargs
end

--- Save lines in a temporary file and send to R a command to source them.
---@param lines string[] Lines to save and source
---@param what string|nil Additional operation to perform
---@return boolean
M.source_lines = function(lines, what)
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
        return true
    end

    local rcmd

    if #lines < config.max_paste_lines then
        rcmd = table.concat(lines, "\n")
        if
            (vim.o.filetype == "rmd" or vim.o.filetype == "quarto")
            and require("r.rmd").is_in_Py_code(false)
        then
            rcmd = rcmd:gsub('"', '\\"')
            rcmd = 'reticulate::py_run_string("' .. rcmd .. '")'
        end
    else
        vim.fn.writefile(lines, config.source_write)
        local sargs = string.gsub(M.get_source_args(), "^, ", "")
        if what then
            if what == "PythonCode" then
                rcmd = 'reticulate::py_run_file("' .. config.source_read .. '")'
            else
                rcmd = "Rnvim." .. what .. "(" .. sargs .. ")"
            end
        else
            rcmd = "NvimR.source(" .. sargs .. ")"
        end
    end

    if config.bracketed_paste then rcmd = "\027[200~" .. rcmd .. "\027[201~" end
    return M.cmd(rcmd)
end

--- Send to R all lines above the current one.
M.above_lines = function()
    local lines = vim.api.nvim_buf_get_lines(0, 1, vim.fn.line(".") - 1, false)

    -- Remove empty lines from the end of the list
    local result =
        table.concat(vim.tbl_filter(function(line) return line ~= "" end, lines), "\n")

    M.cmd(result)
end

M.source_file = function()
    local fpath = vim.api.nvim_buf_get_name(0) .. ".tmp.R"

    if vim.fn.filereadable(fpath) == 1 then
        warn(
            'Cannot create "'
                .. fpath
                .. '" because it already exists. Please, delete it.'
        )
        return
    end

    if config.is_windows then fpath = utils.normalize_windows_path(fpath) end

    local lines = vim.api.nvim_buf_get_lines(0, 0, vim.fn.line("$"), true)

    if #lines > config.max_paste_lines then
        -- Source the file.
        -- Create a temporary copy of the buffer because the file might have
        -- unsaved changes.
        -- Create the temporary file at the same directory because the code might
        -- have commands depending on the current directory not changing and
        -- `vim.o.autochdir` might be `true`.
        vim.fn.writefile(vim.fn.getline(1, "$"), fpath)
        edit.add_for_deletion(fpath)
        local sargs = M.get_source_args()
        local ok = M.cmd('nvimcom:::source.and.clean("' .. fpath .. '"' .. sargs .. ")")
        if not ok then vim.fn.delete(fpath) end
        return
    end

    M.source_lines(lines, nil)
end

-- Send the current paragraph to R. If m == 'down', move the cursor to the
-- first line of the next paragraph.
---@param m boolean True if should move to the next line.
M.paragraph = function(m)
    local start_line, end_line = paragraph.get_current()

    local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line, false)
    M.source_lines(lines, nil)

    if m == true then cursor.move_next_paragraph() end
end

--- Send part of a line
---@param direction string
---@param correctpos boolean
M.line_part = function(direction, correctpos)
    local lin =
        vim.api.nvim_buf_get_lines(0, vim.fn.line(".") - 1, vim.fn.line("."), true)[1]
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
        "Sending function not implemented. "
            .. "It will be either implemented using treesitter or never implemented."
    )
end

--- Send to R Console a command to source the document child indicated in chunk header.
---@param line string The chunck header.
---@param m boolean True if should move to the next chunk.
local knit_child = function(line, m)
    local nline = vim.fn.substitute(line, ".*child *= *", "", "")
    local cfile = vim.fn.substitute(nline, nline:sub(1, 1), "", "")
    cfile = vim.fn.substitute(cfile, nline:sub(1, 1) .. ".*", "", "")
    if vim.fn.filereadable(cfile) == 1 then
        M.cmd("require(knitr); knit('" .. cfile .. "', output=NULL)")
        if m then
            vim.api.nvim_win_set_cursor(0, { vim.fn.line(".") + 1, 1 })
            cursor.move_next_line()
        end
    else
        warn("File not found: '" .. cfile .. "'")
    end
end

--- Send to R Console a command to source a file containing all chunks of here
--- code up to this one.
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
                M.source_lines(codelines, "chunk")
                codelines = {}

                -- Next, run the child chunk and continue
                knit_child(curbuf[idx + 1], false)
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

    M.source_lines(codelines, "chunk")
end

-- Send to R Console the code under a Vim motion
M.motion = function(type)
    local lstart = vim.fn.line("'[")
    local lend = vim.fn.line("']")
    if lstart == lend then
        M.line("stay", lstart)
    else
        local lines = vim.api.nvim_buf_get_lines(0, lstart, lend, true)
        M.source_lines(lines, "block")
    end
end

-- Send block to R (Adapted from marksbrowser plugin)
-- Function to get the marks which the cursor is between
---@param m boolean True if should move to the next line.
M.marked_block = function(m)
    if not vim.b.IsInRCode(true) then return end

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

    local lines = vim.api.nvim_buf_get_lines(0, lineA, lineB, true)
    local ok = M.source_lines(lines, "block")

    if ok == 0 then return end

    if m == true and lineB ~= vim.fn.line("$") then
        vim.fn.cursor(lineB, 1)
        cursor.move_next_line()
    end
end

--- Send to R Console the selected lines
---@param m boolean True if should move to the next line.
M.selection = function(m)
    local ispy = false

    if vim.o.filetype ~= "r" then
        if
            (vim.o.filetype == "rmd" or vim.o.filetype == "quarto")
            and require("r.rmd").is_in_Py_code(0)
        then
            ispy = true
        elseif not vim.b.IsInRCode(false) then
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
        local i = vim.fn.col("'<")
        local j = vim.fn.col("'>") - i
        local l = vim.fn.getline(vim.fn.line("'<"))
        local line = string.sub(l, i, i + j)
        if vim.o.filetype == "r" then line = cursor.clean_oxygen_line(line) end
        local ok = M.cmd(line)
        if ok and m == true then cursor.move_next_line() end
        return
    end

    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, true)
    vim.g.TheVM = vim.fn.visualmode()
    if vim.fn.visualmode() == "\\<C-V>" then
        local cj = vim.fn.col("'<")
        local ck = vim.fn.col("'>")
        if cj > ck then
            local tmp = cj
            cj = ck
            ck = tmp
        end
        local cutlines = {}
        for _, v in pairs(lines) do
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
    if ispy then
        ok = M.source_lines(lines, "PythonCode")
    else
        ok = M.source_lines(lines, "selection")
    end

    if ok == 0 then return end

    if m == true then cursor.move_next_line() end
end

--- Send current line to R Console
---@param m boolean|string Movement to do after sending the line.
---@param lnum number Number of line to send (optional).
M.line = function(m, lnum)
    if not lnum then lnum = vim.fn.line(".") end
    local line = vim.fn.getline(lnum)
    if #line == 0 then
        if m == true then cursor.move_next_line() end
        return
    end

    if
        vim.o.filetype == "rnoweb"
        or vim.o.filetype == "rmd"
        or vim.o.filetype == "quarto"
    then
        if line:find("^<<.*child *= *") or line:find("^```.*child *= *") then
            if type(m) == "boolean" and m then
                knit_child(line, true)
            else
                knit_child(line, false)
            end
            return
        end
    end

    if vim.o.filetype == "rnoweb" then
        if line == "@" then
            if m == true then cursor.move_next_line() end
            return
        end
        if not require("r.rnw").is_in_R_code(true) then return end
    end

    if vim.o.filetype == "rmd" or vim.o.filetype == "quarto" then
        if line == "```" then
            if m == true then cursor.move_next_line() end
            return
        end
        line = vim.fn.substitute(line, "^(\\`\\`)\\?", "", "")
        if not require("r.rmd").is_in_R_code(false) then
            if not require("r.rmd").is_in_Py_code(false) then
                warn("Not inside either R or Python code chunk.")
            else
                line = 'reticulate::py_run_string("' .. line:gsub('"', '\\"') .. '")'
                M.cmd(line)
                if m == true then cursor.move_next_line() end
            end
            return
        end
    end

    if vim.o.syntax == "rdoc" then
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

    local has_op = false
    local lines = {}
    if config.parenblock then
        local chunkend = nil
        if vim.o.filetype == "rmd" or vim.o.filetype == "quarto" then
            chunkend = "```"
        elseif vim.o.filetype == "rnoweb" then
            chunkend = "@"
        end
        has_op = ends_with_operator(line)
        local rpd = paren_diff(line)
        if rpd < 0 or has_op then
            lnum = lnum + 1
            local last_buf_line = vim.fn.line("$")
            lines = { line }
            while lnum <= last_buf_line do
                local txt = vim.fn.getline(lnum)
                if chunkend and txt == chunkend then break end
                table.insert(lines, txt)
                rpd = rpd + paren_diff(txt)
                has_op = ends_with_operator(txt)
                if rpd < 0 or has_op then
                    lnum = lnum + 1
                else
                    vim.fn.cursor(lnum, 1)
                    break
                end
            end
        end
    end

    if #lines > 0 then
        M.source_lines(lines, nil)
    else
        if config.bracketed_paste then
            M.cmd("\027[200~" .. line .. "\027[201~")
        else
            M.cmd(line)
        end
    end

    if m == true then
        cursor.move_next_line()
    elseif m == "newline" then
        vim.cmd("normal! o")
    end
end

return M
