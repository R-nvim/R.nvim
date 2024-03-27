local config = require("r.config").get_config()
local warn = require("r").warn
local utils = require("r.utils")
local edit = require("r.edit")
local cursor = require("r.cursor")
local paragraph = require("r.paragraph")

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

--- Manually set up an R parser for the current quarto/rmd/rnoweb chunk
---@param txt string The text for the line the cursor is currently on
---@param row number The row the cursor is currently on
local ensure_ts_parser_exists = function(txt, row)
    local chunk_start_pattern, chunk_end_pattern

    if vim.o.filetype == "rmd" or vim.o.filetype == "quarto" then
        chunk_start_pattern = "^%s*```"
        chunk_end_pattern = chunk_start_pattern
    elseif vim.o.filetype == "rnoweb" then
        chunk_start_pattern = "^<<"
        chunk_end_pattern = "^@"
    else
        return
    end

    local chunk_start_row = row
    local chunk_end_row = row
    local chunk_txt = txt

    while true do
        chunk_txt = vim.fn.getline(chunk_start_row - 1)
        if chunk_txt:find(chunk_start_pattern) ~= nil then break end
        chunk_start_row = chunk_start_row - 1
    end

    while true do
        chunk_txt = vim.fn.getline(chunk_end_row + 1)
        if chunk_txt:find(chunk_end_pattern) ~= nil then break end
        chunk_end_row = chunk_end_row + 1
    end

    vim.treesitter.get_parser(0, "r"):parse(chunk_start_row, chunk_end_row)
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

    -- Find the 'root' node for the current expression --------------------
    ensure_ts_parser_exists(txt, row)

    local node = vim.treesitter.get_node({
        bufnr = 0,
        pos = { row - 1, col - 1 },
        lang = "r",
        -- Required for quarto/rmd/rnoweb where we need to inject a parser
        ignore_injections = vim.o.filetype == "r",
    })

    local root_nodes = {
        ["program"] = true,
        ["brace_list"] = true,
    }
    local is_root = function(n)
        return root_nodes[n:type()] == true
    end

    while true do
        local parent = node:parent()
        if is_root(parent) then break end
        node = parent
    end

    row = node:end_()

    table.insert(lines, vim.treesitter.get_node_text(node, 0))
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

    local rcmd

    if #lines < config.max_paste_lines then
        rcmd = table.concat(lines, "\n")
        if
            (vim.o.filetype == "rmd" or vim.o.filetype == "quarto")
            and require("r.rmd").is_in_code_chunk("python", false)
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
    local nline = line:gsub(".*child *= *", "")
    local cfile = nline:gsub(nline:sub(1, 1), "")
    cfile = cfile:gsub(nline:sub(1, 1) .. ".*", "")
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
    if not vim.b.IsInRCode(true) then return end

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
        warn("The file has no mark!")
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
    local ispy = false

    if vim.o.filetype ~= "r" then
        if
            (vim.o.filetype == "rmd" or vim.o.filetype == "quarto")
            and require("r.rmd").is_in_code_chunk("python", false)
        then
            ispy = true
        elseif not vim.b.IsInRCode(false) then
            local cline = vim.api.nvim_get_current_line()
            if
                (vim.o.filetype == "rnoweb" and not cline:find("\\Sexpr{"))
                or (
                    (vim.o.filetype == "rmd" or vim.o.filetype == "quarto")
                    and not cline:find("`r ")
                )
            then
                warn("Not inside an R code chunk.")
                return
            end
        end
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
    if ispy then
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
---@param lnum number Number of line to send (optional).
M.line = function(m, lnum)
    if not lnum then lnum = vim.api.nvim_win_get_cursor(0)[1] end
    local line = vim.fn.getline(lnum)

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
        if not require("r.rmd").is_in_code_chunk("r", false) then
            if not require("r.rmd").is_in_code_chunk("python", false) then
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
        local line1 = vim.api.nvim_get_current_line()
        if line1:find("^The topic") then
            local topic = line:gsub(".*::", "")
            local package = line:gsub("::.*", "")
            require("r.rdoc").ask_R_doc(topic, package, true)
            return
        end
        if not require("r.rdoc").is_in_R_code(true) then return end
    end

    if vim.o.filetype == "rhelp" and not require("r.rhelp").is_in_R_code(true) then
        return
    end

    local lines
    lines, lnum = get_code_to_send(line, lnum)

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
        local last_line = vim.api.nvim_buf_line_count(0)
        -- Move to the last line of the sent expression
        vim.api.nvim_win_set_cursor(0, { math.min(lnum + 2, last_line), 0 })
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

local get_root_node = function(bufnr)
    local parser = vim.treesitter.get_parser(bufnr, "r", {})
    local tree = parser:parse()[1]
    return tree:root()
end

-- Send all or the current function to R
M.funs = function(bufnr, capture_all, move_down)
    -- Check if treesitter is available
    local has_treesitter, _ = pcall(require, "nvim-treesitter")
    if not has_treesitter then
        vim.notify(
            "nvim-treesitter is not available. Please install it to use this feature."
        )
        return
    end

    local r_fun_query = vim.treesitter.query.parse(
        "r",
        [[
    (left_assignment
      (function_definition)) @rfun

    (equals_assignment
      (function_definition)) @rfun
    ]]
    )

    bufnr = bufnr or vim.api.nvim_get_current_buf()

    if vim.bo[bufnr].filetype == "quarto" or vim.bo[bufnr].filetype == "rmd" then
        vim.notify("Not yet supported in Rmd or Quarto files.")
        return
    end

    if vim.bo[bufnr].filetype ~= "r" then
        vim.notify("Not an R file.")
        return
    end

    local root_node = get_root_node(bufnr)
    local cursor_pos = vim.api.nvim_win_get_cursor(0)[1]

    local lines = {}

    for id, node in r_fun_query:iter_captures(root_node, bufnr, 0, -1) do
        local name = r_fun_query.captures[id]

        -- Kinda hacky, but it works. Check if the parent of the function is
        -- the root node, if so, it's a top level function
        local s, _, _, _ = node:parent():range()

        if name == "rfun" and s == 0 then
            local start_row, _, end_row, _ = node:range()

            if
                capture_all or (cursor_pos >= start_row + 1 and cursor_pos <= end_row + 1)
            then
                M.source_lines(lines, nil)
                lines = vim.fn.extend(
                    lines,
                    vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
                )
                if move_down == true then
                    vim.api.nvim_win_set_cursor(bufnr, { end_row + 1, 0 })
                    cursor.move_next_line()
                end
            end
        end
    end
    if #lines then M.source_lines(lines) end
end

return M
