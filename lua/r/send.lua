local config = require("r.config").get_config()
local warn = require("r.log").warn
local inform = require("r.log").inform
local utils = require("r.utils")
local get_lang = require("r.utils").get_lang
local edit = require("r.edit")
local cursor = require("r.cursor")
local paragraph = require("r.paragraph")
local get_r_chunks_from_quarto = require("r.quarto").get_r_chunks_from_quarto

--- Check if line is a comment
---@param line string
---@return boolean
local is_comment = function(line) return line:find("^%s*#") ~= nil end

--- Check if a line is blank
---@param line string
---@return boolean
local is_blank = function(line) return line:find("^%s*$") ~= nil end

--- Check if a line is blank or a comment
---@param line string
---@return boolean
local is_insignificant = function(line) return is_comment(line) or is_blank(line) end

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

--- Dumb function to send code without treesitter
---@param txt string The text for the line the cursor is currently on
---@param row number The row the cursor is currently on
---@return table, number
local function get_rhelp_code_to_send(txt, row)
    local lines = { txt }
    local has_op = ends_with_operator(txt)
    local rpd = paren_diff(txt)
    if rpd < 0 or has_op then
        row = row + 1
        local last_buf_line = vim.api.nvim_buf_line_count(0)
        while row <= last_buf_line do
            local line = vim.fn.getline(row)
            table.insert(lines, line)
            rpd = rpd + paren_diff(line)
            has_op = ends_with_operator(line)
            if rpd < 0 or has_op then
                row = row + 1
            else
                vim.api.nvim_win_set_cursor(0, { row, 0 })
                break
            end
        end
    end
    return lines, row - 1
end

--- Get the full expression the cursor is currently on
---@param txt string The text for the line the cursor is currently on
---@param row number The row the cursor is currently on
---@return table, number
local function get_code_to_send(txt, row)
    if not config.parenblock then return {}, row end

    local last_line = vim.api.nvim_buf_line_count(0)
    local lines = {}
    local send_insignificant_lines = false

    -- Find the first non-blank row/column after the cursor ---------------
    while is_insignificant(txt) do
        if is_comment(txt) then send_insignificant_lines = true end
        if send_insignificant_lines then table.insert(lines, txt) end
        if row == last_line then return lines, row end
        row = row + 1
        txt = vim.fn.getline(row)
    end

    local col = txt:find("%S")

    if vim.o.filetype == "rhelp" then return get_rhelp_code_to_send(txt, row) end

    -- Find the 'root' node for the current expression --------------------
    local node = vim.treesitter.get_node({
        bufnr = 0,
        pos = { row - 1, col - 1 },
        -- Required for quarto/rmd/rnoweb; harmless for r.
        ignore_injections = false,
    })

    -- This is a strange fix for https://github.com/R-nvim/R.nvim/issues/298
    if node then vim.schedule(function() end) end

    if node and node:type() == "program" then node = node:child(0) end

    while node do
        local parent = node:parent()
        if
            parent
            and (parent:type() == "program" or parent:type() == "braced_expression")
        then
            break
        end
        node = parent
    end

    if node then
        local start_row, _, end_row, _ = node:range()
        for i = start_row, end_row do
            local line_txt = vim.fn.getline(i + 1)
            table.insert(lines, line_txt)
        end
        row = end_row
    end

    return lines, row
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

    if config.RStudio_cmd ~= "" then
        M.cmd = require("r.rstudio").send_cmd_to_RStudio
    elseif config.external_term == "" then
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

    local rcmd

    if #lines < config.max_paste_lines then
        rcmd = table.concat(lines, "\n")
        if
            (vim.o.filetype == "rmd" or vim.o.filetype == "quarto")
            and get_lang() == "python"
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
            rcmd = "Rnvim.source(" .. sargs .. ")"
        end
    end

    if config.bracketed_paste then rcmd = "\027[200~" .. rcmd .. "\027[201~" end
    return M.cmd(rcmd)
end

--- Send to R all lines above the current one.
M.above_lines = function()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(0, 0, lnum, false)

    -- Remove empty lines
    local filtered_lines = {}

    for _, line in ipairs(lines) do
        if string.match(line, "%S") then table.insert(filtered_lines, line) end
    end

    M.source_lines(filtered_lines, nil)
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

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)

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
    local lin = vim.api.nvim_get_current_line()
    local idx = vim.fn.col(".") - 1
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    if correctpos then vim.api.nvim_win_set_cursor(0, { lnum, idx - 1 }) end
    local rcmd
    if direction == "right" then
        rcmd = string.sub(lin, idx + 1)
    else
        rcmd = string.sub(lin, 1, idx + 1)
    end
    M.cmd(rcmd)
end

--- Send to R Console a command to source the document child indicated in chunk header.
---@param line string The chunk header.
---@param m boolean True if should move to the next chunk.
local knit_child = function(line, m)
    local nline = line:gsub(".*child *[:=] *['\"]", "")
    local cfile = nline:gsub("['\"].*", "")
    if vim.fn.filereadable(cfile) == 1 then
        M.cmd("require(knitr); knit('" .. cfile .. "', output=NULL)")
        if m then
            vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1] + 1, 1 })
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
    local here = vim.api.nvim_win_get_cursor(0)[1]
    local curbuf = vim.fn.getline(1, "$")
    local idx = 0

    local begchk, endchk, chdchk

    if filetype == "rnoweb" then
        begchk = "^<<.*>>=$"
        endchk = "^@"
        chdchk = "^<<.*child *= *"
    elseif filetype == "rmd" or filetype == "quarto" then
        begchk = "^[ \t]*```[ ]*{"
        endchk = "^[ \t]*```$"
        chdchk = "^```.*child *= *"
    else
        -- Should never happen
        warn('Strange filetype (SendFHChunkToR): "' .. filetype .. '"')
        return
    end

    while idx < here do
        if
            curbuf[idx + 1]:find(begchk) and not curbuf[idx + 1]:find("[<, ]eval *= *F")
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
                local lang = "R"
                if filetype == "rmd" or filetype == "quarto" then
                    if curbuf[idx + 1]:find("{python") then
                        lang = "python"
                    elseif not curbuf[idx + 1]:find("{r") then
                        lang = "other"
                    end
                end
                idx = idx + 1
                local i = idx + 1
                local j = idx + 1
                while not curbuf[idx + 1]:match(endchk) and idx < here do
                    -- skip chunk if `eval: false` and `child: *`
                    if curbuf[j]:find("^#| *eval: *false") then
                        j = i - 1
                        break
                    elseif curbuf[j]:find("^#| *child: ") then
                        M.source_lines(codelines, "chunk")
                        codelines = {}
                        knit_child(curbuf[j], false)
                        j = i - 1
                        break
                    end
                    idx = idx + 1
                    j = idx
                end
                local chunklines = {}
                for k = i, j, 1 do
                    table.insert(chunklines, curbuf[k])
                end
                if lang == "python" then
                    table.insert(
                        codelines,
                        'reticulate::py_run_string("'
                            .. table.concat(chunklines, "\n"):gsub('"', '\\"')
                            .. '")'
                    )
                else
                    for _, v in pairs(chunklines) do
                        table.insert(codelines, v)
                    end
                end
            end
        else
            idx = idx + 1
        end
    end

    M.source_lines(codelines, "chunk")
end

-- TODO: Test if this version works: git blame me to see previous version.
-- Send to R Console the code under a Vim motion
M.motion = function()
    local startPos, endPos =
        vim.api.nvim_buf_get_mark(0, "["), vim.api.nvim_buf_get_mark(0, "]")
    local startLine, endLine = startPos[1], endPos[1]

    -- Check if the marks are valid
    if
        startLine <= 0
        or startLine > endLine
        or endLine > vim.api.nvim_buf_line_count(0)
    then
        warn("Invalid motion range")
        return
    end

    -- Adjust endLine to include the line under the ']` mark
    endLine = endLine < vim.api.nvim_buf_line_count(0) and endLine or endLine - 1

    -- Fetch the lines from the buffer
    local lines = vim.api.nvim_buf_get_lines(0, startLine - 1, endLine, false)

    -- Send the fetched lines to be sourced by R
    if lines and #lines > 0 then
        M.source_lines(lines, "block")
    else
        warn("No lines to send")
    end
end

-- Send block to R (Adapted from marksbrowser plugin)
-- Function to get the marks which the cursor is between
---@param m boolean True if should move to the next line.
M.marked_block = function(m)
    if get_lang() ~= "r" then
        inform("Not in R code.")
        return
    end

    local last_line = vim.api.nvim_buf_line_count(0)

    local curline = vim.api.nvim_win_get_cursor(0)[1]
    local lineA = 1
    local lineB = last_line
    local lnum
    local n = string.byte("a")
    local z = string.byte("z")

    while n <= z do
        lnum = vim.api.nvim_buf_get_mark(0, string.char(n))[1]
        if lnum ~= 0 then
            if lnum <= curline and lnum > lineA then
                lineA = lnum
            elseif lnum > curline and lnum < lineB then
                lineB = lnum
            end
        end
        n = n + 1
    end

    if lineA == 1 and lineB == last_line then
        inform("The file has no mark!")
        return
    end

    if lineB < last_line then lineB = lineB - 1 end

    local lines = vim.api.nvim_buf_get_lines(0, lineA - 1, lineB, true)
    local ok = M.source_lines(lines, "block")

    if ok == 0 then return end

    if m == true and lineB ~= last_line then
        vim.api.nvim_win_set_cursor(0, { lineB, 0 })
        cursor.move_next_line()
    end
end

--- Send to R Console the selected lines
---@param m boolean True if should move to the next line.
M.selection = function(m)
    local lang = get_lang()

    if
        (vim.o.filetype == "rmd" or vim.o.filetype == "quarto")
        and lang ~= "r"
        and lang ~= "python"
        and not vim.api.nvim_get_current_line():find("`r ")
    then
        inform("Not inside R or Python code chunk.")
        return
    end

    if
        vim.o.filetype == "rnoweb"
        and lang ~= "r"
        and not vim.api.nvim_get_current_line():find("\\Sexpr{")
    then
        inform("Not inside R code chunk.")
        return
    end

    -- Leave visual mode
    local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(esc, "x", false)

    local start_pos = vim.api.nvim_buf_get_mark(0, "<")
    local end_pos = vim.api.nvim_buf_get_mark(0, ">")
    local lines = vim.api.nvim_buf_get_lines(0, start_pos[1] - 1, end_pos[1], true)

    local vmode = vim.fn.visualmode()
    if vmode == "\022" then
        -- "\022" is <C-V>
        local cj = start_pos[2] + 1
        local ck = end_pos[2] + 1
        if cj > ck then
            local tmp = cj
            cj = ck
            ck = tmp
        end
        for k, _ in pairs(lines) do
            lines[k] = string.sub(lines[k], cj, ck)
        end
    elseif vmode == "v" then
        if start_pos[1] == end_pos[1] then
            lines[1] = string.sub(lines[1], start_pos[2] + 1, end_pos[2] + 1)
        else
            lines[1] = string.sub(lines[1], start_pos[2] + 1, -1)
            local llen = #lines
            lines[llen] = string.sub(lines[llen], 1, end_pos[2] + 1)
        end
    end

    if vim.o.filetype == "r" then
        for k, _ in ipairs(lines) do
            lines[k] = cursor.clean_oxygen_line(lines[k])
        end
    end

    local ok
    if lang == "python" then
        ok = M.source_lines(lines, "PythonCode")
    else
        ok = M.source_lines(lines, "selection")
    end

    if ok == 0 then return end

    if m == true then
        vim.api.nvim_win_set_cursor(0, end_pos)
        cursor.move_next_line()
    end
end

--- Send current line to R Console
---@param m boolean|string Movement to do after sending the line.
M.line = function(m)
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.fn.getline(lnum)
    local lang = get_lang()
    if lang == "chunk_child" then
        if type(m) == "boolean" and m then
            knit_child(line, true)
        else
            knit_child(line, false)
        end
        return
    elseif lang == "chunk_end" then
        if m == true then
            if vim.bo.filetype == "rnoweb" then
                require("r.rnw").next_chunk()
            else
                require("r.rmd").next_chunk()
            end
        end
        return
    end

    local ok = false
    if
        vim.bo.filetype == "rnoweb"
        or vim.bo.filetype == "rmd"
        or vim.bo.filetype == "quarto"
    then
        if lang == "python" then
            line = 'reticulate::py_run_string("' .. line:gsub('"', '\\"') .. '")'
            ok = M.cmd(line)
            if ok and m == true then cursor.move_next_line() end
            return
        end
        if lang ~= "r" then
            inform("Not inside R or Python code chunk [within " .. lang .. "]")
            return
        end
    end

    if vim.bo.filetype == "rhelp" and lang ~= "r" then
        inform("Not inside an R section.")
        return
    end

    local lines
    lines, lnum = get_code_to_send(line, lnum)

    if #lines > 1 then
        ok = M.source_lines(lines, nil)
    else
        if #lines == 1 then line = lines[1] end
        if config.bracketed_paste then
            ok = M.cmd("\027[200~" .. line .. "\027[201~")
        else
            ok = M.cmd(line)
        end
    end

    if ok and m == true then
        local last_line = vim.api.nvim_buf_line_count(0)
        -- Move to the last line of the sent expression
        vim.api.nvim_win_set_cursor(0, { math.min(lnum + 1, last_line), 0 })
        -- Move to the start of the next expression
        -- Should this be changed to move you to the start of the next comment,
        -- now that sending from that location will also cause the next bit
        -- of significant code to be sent?
        cursor.move_next_line()
    elseif m == "newline" then
        vim.cmd("normal! o")
    end
end

-- Function to check if a string ends with a specific suffix
---@param str string
---@param suffix string
---@return boolean
local function ends_with(str, suffix) return str:sub(-#suffix) == suffix end

local function trim_lines(array)
    local result = {} -- Create a new table to store the trimmed lines

    for i = 1, #array do
        local line = array[i]
        local trimmedLine = line:match("^%s*(.-)%s*$") -- Remove leading and trailing whitespace
        table.insert(result, trimmedLine) -- Add the trimmed line to the result table
    end

    return result
end

-- Remove the <-, |>/%>% or + from the text
---@param array string[]
---@return string[]
local function sanatize_text(array)
    local firstString = array[1]
    -- Remove "<-" and everything before it from the first string
    local modifiedFirstString = firstString:gsub(".*<%-%s*", "")
    array[1] = modifiedFirstString

    local lastIndex = #array
    local lastString = array[lastIndex]

    -- Check if the last string ends with either "|>" or "%>%"
    local modifiedString =
        lastString:gsub("|>[%s]*$", ""):gsub("%%>%%[%s]*$", ""):gsub("%+[%s]*$", "")
    array[lastIndex] = modifiedString

    return array
end

--- Check if string ends in one of specific pre-defined patterns
---@param str string
---@return boolean
function ends_with(str)
    return string.match(str, "[|%%]%>%%?[%s]*$") ~= nil
        or string.match(str, "%+[%s]*$") ~= nil
        or string.match(str, "%([%s]*$") ~= nil
end

--- Return the line where piped chain begins
---@param arr string[]
---@return number
local function chain_start_at(arr)
    for i = 1, #arr do
        if ends_with(arr[i]) then return i end
    end

    return #arr
end

--- Send the above chain of piped commands
M.chain = function()
    -- Get the current line, the start and end line of the paragraph
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    local startLine = vim.fn.search("^$", "bnW") -- Search for previous empty line
    local endLine = vim.fn.search("^$", "nW") - 1 -- Search for next empty line and adjust for exclusive range

    -- Get the paragraph lines
    local paragraphLines = vim.api.nvim_buf_get_lines(0, startLine, endLine, false)
    paragraphLines = trim_lines(paragraphLines)

    -- Get the relative line number within the paragraph
    local relativeLineNumber = current_line - startLine

    paragraphLines = trim_lines(paragraphLines)

    local extractedLines = {}
    for i = 1, relativeLineNumber do
        table.insert(extractedLines, paragraphLines[i])
    end

    -- Find the starting line of the chain
    local lineChainStartAt = chain_start_at(extractedLines)

    local chain = {}

    for i = lineChainStartAt, relativeLineNumber do
        table.insert(chain, extractedLines[i])
    end

    chain = sanatize_text(chain)

    M.source_lines(chain, nil)
end

-- local get_root_node = function(bufnr)
--     local parser = vim.treesitter.get_parser(bufnr, "r", {})
--     if not parser then return nil end
--     local tree = parser:parse()[1]
--     return tree:root()
-- end

-- Helper function to get the root node
local function get_root_node(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local parser = vim.treesitter.get_parser(bufnr)

    if not parser then return nil end

    local tree = parser:parse()[1]

    return tree:root()
end

--- Extracts R functions from the given R content based on the query and cursor position.
-- @param r_content The R content as a string.
-- @param capture_all Boolean indicating whether to capture all functions.
-- @param cursor_pos The current cursor position.
-- @param chunk_start_row The starting row of the chunk.
-- @return A table containing the extracted function lines.
local extract_r_functions = function(r_content, capture_all, cursor_pos, chunk_start_row)
    local r_parser = vim.treesitter.get_string_parser(r_content, "r")
    local r_tree = r_parser:parse()[1]
    local r_root = r_tree:root()

    local r_fun_query = vim.treesitter.query.parse(
        "r",
        [[
        (binary_operator
          (function_definition)) @rfun
        ]]
    )

    local lines = {}

    for _, node in r_fun_query:iter_captures(r_root, r_content) do
        local start_row, _, end_row, _ = node:range()

        -- Adjust the cursor position relative to the chunk start
        local adjusted_cursor_pos = cursor_pos - (chunk_start_row or 0)

        if
            capture_all
            or (
                adjusted_cursor_pos >= start_row + 1
                and adjusted_cursor_pos <= end_row + 1
            )
        then
            local function_lines = vim.treesitter.get_node_text(node, r_content)
            vim.list_extend(lines, { function_lines })
        end
    end

    return lines
end

M.funs = function(bufnr, capture_all, move_down)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local filetype = vim.bo[bufnr].filetype

    if
        filetype ~= "r"
        and filetype ~= "rnoweb"
        and filetype ~= "quarto"
        and filetype ~= "rmd"
    then
        inform("Not yet supported in '" .. filetype .. "' files.")
        return
    end

    local root_node = get_root_node(bufnr)
    if not root_node then return end

    local cursor_pos = vim.api.nvim_win_get_cursor(0)[1]

    local lines = {}

    if filetype == "quarto" or filetype == "rmd" then
        local r_chunks_content = get_r_chunks_from_quarto(root_node, bufnr)

        for _, r_chunk in ipairs(r_chunks_content) do
            local chunk_lines = extract_r_functions(
                r_chunk.content,
                capture_all,
                cursor_pos,
                r_chunk.start_row
            )
            vim.list_extend(lines, chunk_lines)
        end
    else
        local buffer_content =
            table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
        lines = extract_r_functions(buffer_content, capture_all, cursor_pos)
    end

    if #lines > 0 then
        M.source_lines(lines)
        if move_down == true then
            local last_function = lines[#lines]
            local function_lines = vim.split(last_function, "\n")
            local end_row = vim.api.nvim_win_get_cursor(0)[1] + #function_lines
            vim.api.nvim_win_set_cursor(0, { end_row, 0 })
            vim.cmd("normal! j")
        end
    end
end
return M
