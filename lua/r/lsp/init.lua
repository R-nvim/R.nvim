local send_to_nvimcom = require("r.run").send_to_nvimcom
local warn = require("r.log").warn

local client_id

local qcell_opts = false
local compl_region = true
local lsp_debug = false

local options = require("r.config").get_config().r_ls or {}

local M = {}

local get_piped_obj

---Return object piped through either `|>` or `%>%`
---@param line string | nil
---@param lnum integer
---@return string | nil
get_piped_obj = function(line, lnum)
    local l
    l = vim.fn.getline(lnum - 1)
    if l then
        if l:find("|>%s*$") then return get_piped_obj(l, lnum - 1) end
        if l:find("%%>%%%s*$") then return get_piped_obj(l, lnum - 1) end
    end
    if line then
        if line:find("|>") then return line:match(".-([%w%._]+)%s*|>") end
        if line:find("%%>%%") then return line:match(".-([%w%._]+)%s*%%>%%") end
    end
    return nil
end

---Return first argument of function
---@param line string
---@param lnum integer
local get_first_obj = function(line, lnum)
    -- The function with the same name in r.cursor has a different purpose.
    -- r.cursor.get_first_obj: the cursor is expected to be over the function
    -- r.lsp.get_first_obj: the cursor is expected to be between the parentheses.
    local no
    local piece
    local funname
    local firstobj
    local pkg
    no = 0
    local op
    op = string.byte("(")
    local cp
    cp = string.byte(")")
    local idx
    repeat
        idx = #line
        while idx > 0 do
            if line:byte(idx) == op then
                no = no + 1
            elseif line:byte(idx) == cp then
                no = no - 1
            end
            if no == 1 then
                -- The opening parenthesis is here. Now, get the function and
                -- its first object (if in the same line)
                piece = string.sub(line, 1, idx - 1)
                funname = string.match(piece, ".-([%w%._]+)%s*$")
                if funname then pkg = string.match(piece, ".-([%w%._]+)::" .. funname) end
                piece = string.sub(line, idx + 1)
                firstobj = string.match(piece, "%s-([%w%.%_]+)")
                if funname then idx = string.find(line, funname) end
                break
            end
            idx = idx - 1
        end
        if funname then break end
        lnum = lnum - 1
        if lnum == 0 then break end
        line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
    until line:find("^%S")
    return pkg, funname, firstobj, line, lnum, idx
end

---Check if we need to complete function arguments
---@param line string
---@param lnum integer
local need_R_args = function(line, lnum)
    local funname = nil
    local firstobj = nil
    local funname2 = nil
    local firstobj2 = nil
    local listdf = nil
    local nline = nil
    local nlnum = nil
    local cnum = nil
    local lib = nil
    lib, funname, firstobj, nline, nlnum, cnum = get_first_obj(line, lnum + 1)

    -- Check if this is a function for which we expect to complete data frame column names
    if funname then
        -- Check if the data.frame is supposed to be the first argument:
        for _, v in pairs(options.fun_data_1) do
            if v == funname then
                listdf = 1
                break
            end
        end

        -- Check if the data.frame is supposed to be the first argument of the
        -- nesting function:
        if not listdf and cnum > 1 then
            nline = string.sub(nline, 1, cnum)
            for k, v in pairs(options.fun_data_2) do
                for _, a in pairs(v) do
                    if a == "*" or funname == a then
                        _, funname2, firstobj2, nline, nlnum, _ =
                            get_first_obj(nline, nlnum)
                        if funname2 == k then
                            firstobj = firstobj2
                            listdf = 2
                            break
                        end
                    end
                end
            end
        end
    end

    -- Check if the first object was piped
    local pobj = get_piped_obj(nline, nlnum)
    if pobj then firstobj = pobj end
    local resp
    resp = {
        lib = lib,
        fnm = funname,
        fnm2 = funname2,
        firstobj = firstobj,
        listdf = listdf,
        firstobj2 = firstobj2,
        pobj = pobj,
    }
    return resp
end

local warned_no_reset = false
local reset_r_compl = function()
    if warned_no_reset then return end
    vim.notify("NOT IMPLEMENTED: reset_r_compl")
    warned_no_reset = true
end

--- Get the word before the cursor, considering that Unicode
--- characters use more bytes than occupy display cells
---@param line string Current line
---@param cnum integer Cursor position in number of display cells
---@param pttrn? string Pattern to get word for completion
local get_word = function(line, cnum, pttrn)
    local i = cnum
    local preline
    while true do
        preline = line:sub(1, i)
        if cnum == vim.fn.strwidth(preline) then break end
        i = i + 1
    end
    local pattern = pttrn and pttrn
        or "([%a\192-\244\128-\191_.][%w_.@$\192-\244\128-\191]*)$"
    local wrd = preline:match(pattern)
    return wrd
end

---Identify what should be completed and send request back to rnvimserver
---@param req_id string
---@param lnum integer
---@param cnum integer
function M.complete(req_id, lnum, cnum)
    if not compl_region then return end
    -- In cmp-r: cline = request.context.cursor_before_line
    local cline = vim.api.nvim_buf_get_lines(0, lnum, lnum + 1, true)[1]

    local wrd = get_word(cline, cnum)

    -- Check if this is Rmd and the cursor is in the chunk header
    if vim.bo.filetype == "rmd" and cline:find("^```{r") then
        if wrd then
            M.send_msg({ code = "CC", orig_id = req_id, base = wrd })
        else
            M.send_msg({ code = "CC", orig_id = req_id })
        end
        return
    end

    -- Check if the cursor is in R code
    local lang = "r"
    if vim.bo.filetype ~= "r" then
        lang = "other"
        local lines = vim.api.nvim_buf_get_lines(0, 0, lnum, true)
        if vim.bo.filetype == "rmd" or vim.bo.filetype == "quarto" then
            lang = require("r.utils").get_lang()
            if lang == "markdown_inline" then
                local wrd2 = get_word(cline, cnum, "(@[tf]%S*)")
                if wrd2 and wrd2:find("^@") then
                    local lbls = require("r.lsp.figtbl").get_labels(wrd2)
                    M.send_msg({ code = "C@", orig_id = req_id, items = lbls })
                end
                return
            end
        elseif vim.bo.filetype == "rnoweb" then
            for i = lnum, 1, -1 do
                if string.find(lines[i], "^%s*<<.*>>=") then
                    lang = "r"
                    break
                elseif string.find(lines[i], "^@") then
                    return
                end
            end
        elseif vim.bo.filetype == "rhelp" then
            for i = lnum, 1, -1 do
                if string.find(lines[i], [[\%S+{]]) then
                    if
                        string.find(lines[i], [[\examples{]])
                        or string.find(lines[i], [[\usage{]])
                    then
                        lang = "r"
                    end
                    break
                end
            end
            if lang ~= "r" then
                if cline:sub(cnum, cnum) == "\\" then
                    M.send_msg({ code = "CH", orig_id = req_id })
                end
                return
            end
        end
    end

    -- Is the current cursor position within the YAML header of an R or Python block of code?
    if (lang == "r" or lang == "python") and cline:find("^#| ") then
        if cline:find("^#| .*:") and not cline:find("^#| .*: !expr ") then return nil end
        if not cline:find("^#| .*: !expr ") then
            if not qcell_opts then
                qcell_opts = require("r.lsp.quarto").get_cell_opts(options.quarto_intel)
            end
            if wrd then
                M.send_msg({ code = "CB", orig_id = req_id, base = wrd })
            else
                M.send_msg({ code = "CB", orig_id = req_id })
            end
            return
        end
    end

    if lang ~= "r" then return end

    -- check if the cursor is within comment or string
    local snm = ""
    local c = vim.treesitter.get_captures_at_pos(0, lnum, cnum - 1)
    if #c > 0 then
        for _, v in pairs(c) do
            if v.capture == "string" then
                snm = "rString"
            elseif v.capture == "comment" then
                return
            end
        end
    elseif vim.bo.filetype == "rhelp" then
        -- We still need to call synIDattr because there is no treesitter parser for rhelp
        snm = vim.fn.synIDattr(vim.fn.synID(lnum, cnum - 1, 1), "name")
        if snm == "rComment" then return nil end
    end

    -- Should we complete function arguments?
    local nra
    nra = need_R_args(cline:sub(1, cnum), lnum)

    if nra.fnm then
        -- We are passing arguments for a function.

        -- Special completion for library and require
        if
            (nra.fnm == "library" or nra.fnm == "require")
            and (not nra.firstobj or nra.firstobj == wrd)
        then
            M.send_msg({ code = "5", orig_id = req_id, base = wrd, fnm = "#" })
            return
        end

        if snm == "rString" then return end

        if vim.g.R_Nvim_status < 7 then
            -- Get the arguments of the first function whose name matches nra.fnm
            if nra.lib then
                M.send_msg({
                    code = "5",
                    orig_id = req_id,
                    base = wrd,
                    fnm = nra.lib .. "::" .. nra.fnm,
                })
            else
                M.send_msg({ code = "5", orig_id = req_id, base = wrd, fnm = nra.fnm })
            end
            return
        else
            -- Request arguments according to class of first object
            local msg
            msg = string.format(
                "nvimcom:::nvim_complete_args('%s', '%s', '%s'",
                req_id,
                nra.fnm,
                wrd and wrd or " "
            )
            if nra.firstobj then
                msg = msg .. ", firstobj = '" .. nra.firstobj .. "'"
            elseif nra.lib then
                msg = msg .. ", lib = '" .. nra.lib .. "'"
            end
            if nra.firstobj and nra.listdf then msg = msg .. ", ldf = TRUE" end
            msg = msg .. ")"
            send_to_nvimcom("E", msg)
            return
        end
    end

    if snm == "rString" then return nil end

    if not wrd then
        reset_r_compl()
        return
    end

    M.send_msg({ code = "5", orig_id = req_id, base = wrd })
end

local get_function_name = function()
    local cpos = vim.api.nvim_win_get_cursor(0)
    if not cpos then return nil end
    local cnum = cpos[2]
    local lnum = cpos[1] - 1
    local cline = vim.api.nvim_buf_get_lines(0, lnum, lnum + 1, true)[1]
    local nra = need_R_args(cline:sub(1, cnum), lnum)
    return nra.fnm
end

---Identify what object should its details displayed on hover
---@param req_id string
M.hover = function(req_id)
    local word = require("r.cursor").get_keyword()
    local c = vim.treesitter.get_captures_at_cursor()

    if vim.tbl_contains(c, "function.call") then
        local first_obj = require("r.cursor").get_first_obj()
        M.send_msg({ code = "H", orig_id = req_id, word = word, fobj = first_obj })
    elseif vim.tbl_contains(c, "variable.parameter") then
        local fnm = get_function_name()
        if fnm then
            M.send_msg({ code = "H", orig_id = req_id, word = word, fnm = fnm })
        end
    elseif vim.tbl_contains(c, "variable") then
        M.send_msg({ code = "H", orig_id = req_id, word = word })
    end
end

---Identify what object should its details displayed on hover
---@param req_id string
M.signature = function(req_id)
    local fnm = get_function_name()
    if fnm then
        -- triggered by `(`
        M.send_msg({ code = "S", orig_id = req_id, word = fnm })
    else
        -- triggered manually
        local word = require("r.cursor").get_keyword()
        if word and word ~= ")" then
            M.send_msg({ code = "S", orig_id = req_id, word = word })
        else
            vim.notify("WORD:" .. vim.inspect(word) .. "\nFNM:" .. vim.inspect(fnm))
        end
    end
end

--- Execute lua command sent by rnvimserver
local function exe_cmd(_, result, _)
    vim.schedule(function()
        local f = loadstring(result.command)
        if f then f() end
    end)
end

--- Callback invoked when client attaches to a buffer.
---@param client vim.lsp.Client
---@param bnr integer
local function on_attach(client, bnr)
    local msg = string.format("LSP_on_attach (%d, %d)", client.id, bnr)
    vim.notify(msg)
end

--- Callback invoked after LSP "initialize"
---@param client vim.lsp.Client
---@param _ lsp.InitializeResult
local function on_init(client, _)
    local msg = string.format("r_ls init (%d)", client.id)
    vim.notify(msg)
end

--- Callback invoked on client exit.
---@param code integer Exit code of the process
---@param signal integer Number describing the signal used to terminate (if any)
---@param client integer Client handle
local function on_exit(code, signal, client)
    vim.g.R_Nvim_status = 1
    if code == 0 then return end
    local msg = string.format("r_ls exit (%d, %d, %d)", code, signal, client)
    vim.notify(msg)
end

--- Callback invoked when the client operation prints to stderr
--- @param code number Number describing the error. See vim.lsp.rpc.client_errors
--- @param err string Error message
local function on_error(code, err)
    local msg = string.format("r_ls error (%d):\n%s", code, err)
    vim.notify(msg)
end

--- Start rnvimserver
---@param rns_path string Full rnvimserver path
---@param rns_env table Environment variables
function M.start(rns_path, rns_env)
    -- TODO: remove this when nvim 0.12 is released
    if not vim.lsp.config then return end

    vim.lsp.config("r_ls", {})

    client_id = vim.lsp.start({
        name = "r_ls",
        cmd = { rns_path },
        -- cmd = {
        --     "valgrind",
        --     "--leak-check=full",
        --     "--log-file=/tmp/rnvimserver_valgrind_log",
        --     rns_path,
        -- },
        cmd_env = rns_env,
        on_init = lsp_debug and on_init or nil,
        on_attach = lsp_debug and on_attach or nil,
        on_exit = on_exit,
        on_error = on_error,
        trace = lsp_debug and "verbose" or nil,
        handlers = {
            ["client/exeRnvimCmd"] = exe_cmd,
        },
    })
    if client_id then vim.lsp.completion.enable(true, client_id, 0) end
end

---Send a custom notification to rnvimserver
---@param params table A valid json LSP params
function M.send_msg(params)
    local buf = require("r.edit").get_rscript_buf()
    -- lua_ls will warn that "exeRnvimCmd" is not a valid method
    local res = vim.lsp.buf_notify(buf, "exeRnvimCmd", params)
    if lsp_debug and not res then
        warn("Failed to send message to r_ls: " .. vim.inspect(params))
    end
end

-- TODO: check if need_R_args is working well in all cases
-- This is a temporary function and should be deleted when need_R_args is well
-- tested (before merging the "lsp" branch). To run this function, put at the
-- end of your init.lua:
-- vim.keymap.set("n", "<F5>", '<Cmd>lua require("r.lsp").call_nra()<CR>')
M.call_nra = function()
    local cpos = vim.api.nvim_win_get_cursor(0)
    if not cpos then return end
    local cnum = cpos[2]
    local lnum = cpos[1] - 1
    local cline = vim.api.nvim_buf_get_lines(0, lnum, lnum + 1, true)[1]
    local nra = need_R_args(cline:sub(1, cnum), lnum)
    vim.notify("NRA: " .. vim.inspect(nra))
end

return M
