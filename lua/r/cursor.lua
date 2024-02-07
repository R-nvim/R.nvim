local M = {}

--- Remove leading spaces and trailing comments from string
---@param line string Line to clean
local clean_current_line = function(line)
    local cleanline = line:gsub("^%s*", "")
    cleanline = cleanline:gsub("#.*", "")
    if vim.o.filetype == "r" then cleanline = M.clean_oxygen_line(cleanline) end
    return cleanline
end

M.clean_oxygen_line = function(line)
    if line:find("^%s*#'") then
        local synID = vim.fn.synID(vim.fn.line("."), vim.fn.col("."), 1)
        local synName = vim.fn.synIDattr(synID, "name")
        if synName == "rOExamples" then line = string.gsub(line, "^%s*#'", "") end
    end
    return line
end

-- Returns the line number of the first non-empty line after the current
-- paragraph. If the cursor is on the last paragraph, returns the last line
-- number.
M.find_next_paragraph = function()
    local current_line = vim.fn.line(".")
    local next_empty_line = current_line

    -- Search for the next empty line (paragraph separator)
    while next_empty_line <= vim.fn.line("$") do
        if vim.fn.trim(vim.fn.getline(next_empty_line)) == "" then break end
        next_empty_line = next_empty_line + 1
    end

    -- Move cursor to the first non-empty line after the empty line
    while next_empty_line <= vim.fn.line("$") do
        if vim.fn.trim(vim.fn.getline(next_empty_line)) ~= "" then
            return next_empty_line
        end
        next_empty_line = next_empty_line + 1
    end

    return vim.fn.line("$")
end

-- Moves the cursor to the first non-empty line after the current paragraph.
M.move_next_paragraph = function()
    vim.api.nvim_win_set_cursor(0, { M.find_next_paragraph(), 0 })
end

-- Moe the cursor to the next line
M.move_next_line = function()
    local lnum = vim.fn.line(".")
    if lnum == vim.fn.line("$") then return end

    local filetype = vim.o.filetype
    local has_code = false
    while not has_code do
        lnum = lnum + 1
        local curline = clean_current_line(vim.fn.getline(lnum))
        if filetype == "rnoweb" and string.sub(curline, 1, 1) == "@" then
            require("r.rnw").next_chunk()
            return
        elseif (filetype == "rmd" or filetype == "quarto") and curline:find("^```$") then
            require("r.rmd").next_chunk()
            return
        end
        if #curline > 0 then break end
    end
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
end

M.get_first_obj = function(rkeyword)
    local firstobj = ""
    local line = vim.fn.substitute(vim.fn.getline(vim.fn.line(".")), "#.*", "", "")
    local begin = vim.fn.col(".")

    if vim.fn.strlen(line) > begin then
        local piece = vim.fn.substitute(vim.fn.strpart(line, begin), "\\s*$", "", "")
        while not piece:find("^" .. rkeyword) and begin >= 0 do
            begin = begin - 1
            piece = vim.fn.strpart(line, begin)
        end

        -- check if the first argument is being passed through a pipe operator
        if begin > 2 then
            local part1 = vim.fn.strpart(line, 0, begin)
            if part1:find("%k+\\s*\\(|>\\|%>%\\)\\s*") then
                local pipeobj = vim.fn.substitute(
                    part1,
                    ".\\{-}\\(\\k\\+\\)\\s*\\(|>\\|%>%\\)\\s*",
                    "\\1",
                    ""
                )
                return { pipeobj, true }
            end
        end

        local pline =
            vim.fn.substitute(vim.fn.getline(vim.fn.line(".") - 1), "#.*$", "", "")
        if pline:find("\\k+\\s*\\(|>\\|%>%\\)\\s*$") then
            local pipeobj = vim.fn.substitute(
                pline,
                ".\\{-}\\(\\k\\+\\)\\s*\\(|>\\|%>%\\)\\s*$",
                "\\1",
                ""
            )
            return { pipeobj, true }
        end

        line = piece
        if not line:find("^\\k*\\s*(") then return { firstobj, false } end
        begin = 1
        local linelen = vim.fn.strlen(line)
        while line:sub(begin, begin) ~= "(" and begin < linelen do
            begin = begin + 1
        end
        begin = begin + 1
        line = vim.fn.strpart(line, begin)
        line = vim.fn.substitute(line, "^\\s*", "", "")
        if
            (line:find("^\\k*\\s*\\(") or line:find("^\\k*\\s*=\\s*\\k*\\s*\\("))
            and not line:find("[.*(")
        then
            local idx = 0
            while line:sub(idx, idx) ~= "(" do
                idx = idx + 1
            end
            idx = idx + 1
            local nparen = 1
            local len = vim.fn.strlen(line)
            local lnum = vim.fn.line(".")
            while nparen ~= 0 do
                if idx == len then
                    lnum = lnum + 1
                    while
                        lnum <= vim.fn.line("$")
                        and vim.fn.strlen(
                                vim.fn.substitute(vim.fn.getline(lnum), "#.*", "", "")
                            )
                            == 0
                    do
                        lnum = lnum + 1
                    end
                    if lnum > vim.fn.line("$") then return { "", false } end
                    line = line .. vim.fn.substitute(vim.fn.getline(lnum), "#.*", "", "")
                    len = vim.fn.strlen(line)
                end
                if line:sub(idx, idx) == "(" then
                    nparen = nparen + 1
                else
                    if line:sub(idx, idx) == ")" then nparen = nparen - 1 end
                end
                idx = idx + 1
            end
            firstobj = vim.fn.strpart(line, 0, idx)
        elseif
            line:find("^\\(\\k\\|\\$\\)*\\s*\\[")
            or line:find("^\\(k\\|\\$\\)*\\s*=\\s*\\(\\k\\|\\$\\)*\\s*[.*(")
        then
            local idx = 0
            while line:sub(idx, idx) ~= "[" do
                idx = idx + 1
            end
            idx = idx + 1
            local nparen = 1
            local len = vim.fn.strlen(line)
            local lnum = vim.fn.line(".")
            while nparen ~= 0 do
                if idx == len then
                    lnum = lnum + 1
                    while
                        lnum <= vim.fn.line("$")
                        and vim.fn.strlen(
                                vim.fn.substitute(vim.fn.getline(lnum), "#.*", "", "")
                            )
                            == 0
                    do
                        lnum = lnum + 1
                    end
                    if lnum > vim.fn.line("$") then return { "", false } end
                    line = line .. vim.fn.substitute(vim.fn.getline(lnum), "#.*", "", "")
                    len = vim.fn.strlen(line)
                end
                if line:sub(idx, idx) == "[" then
                    nparen = nparen + 1
                else
                    if line:sub(idx, idx) == "]" then nparen = nparen - 1 end
                end
                idx = idx + 1
            end
            firstobj = vim.fn.strpart(line, 0, idx)
        else
            firstobj = vim.fn.substitute(line, ").*", "", "")
            firstobj = vim.fn.substitute(firstobj, ",.*", "", "")
            firstobj = vim.fn.substitute(firstobj, " .*", "", "")
        end
    end

    if firstobj:find("=" .. vim.fn.char2nr('"')) then firstobj = "" end

    if firstobj:sub(1, 1) == '"' or firstobj:sub(1, 1) == "'" then
        firstobj = "#c#"
    elseif firstobj:sub(1, 1) >= "0" and firstobj:sub(1, 1) <= "9" then
        firstobj = "#n#"
    end

    if firstobj:find('"') then firstobj = vim.fn.substitute(firstobj, '"', '\\"', "g") end

    return { firstobj, false }
end

return M
