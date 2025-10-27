local send_to_nvimcom = require("r.run").send_to_nvimcom
local warn = require("r.log").warn

local client_id

-- local ter = nil
local qcell_opts = false
local compl_region = true
local lsp_debug = false

-- TODO: incorporate the options into normal R.nvim config at lua/r/config.lua
local options = {
    doc_width = 58,
    trigger_characters = { ".", " ", ":", "(", '"', "@", "$" }, -- TODO: different trigger_characters for different filetypes
    fun_data_1 = { "select", "rename", "mutate", "filter" },
    fun_data_2 = { ggplot = { "aes" }, with = { "*" } },
    quarto_intel = nil,
}

-- TODO: delete this table before merging the pull request
-- Correspondence between nvimcom "cls" and LSP "kind".
--    old    new    LSP name         R type
--    ["("]  ["F"]  Function         function
--    ["$"]  ["d"]  Struct           data.frame
--    ["%"]  ["b"]  Method           logical
--    ["~"]  ["t"]  Text             character
--    ["{"]  ["n"]  Value            numeric
--    ["!"]  ["f"]  Field            factor
--    [";"]  ["C"]  Constructor      control
--    ["["]  ["l"]  Struct           list
--    ["<"]  ["4"]  Class            S4
--    [">"]  ["7"]  Class            S7
--    [":"]  ["e"]  Interface        environment
--    ["&"]  ["p"]  Event            promise
--    ["l"]  ["L"]  Module           library
--    ["a"]  ["a"]  Variable         function argument
--    ["c"]  ["c"]  Field            data.frame column
--    ["*"]  ["o"]  TypeParameter    other

-- This function should never be called. It should be deleted when we consider
-- the LSP completion free of logical bugs.
local err_msg = function(msg)
    local info = debug.getinfo(1, "S").short_src
    vim.notify(info .. ":\n\n" .. msg, vim.log.levels.ERROR, { title = "r_ls" })
end

local M = {}

local fix_doc = function(txt)
    -- The rnvimserver replaces ' with \019 and \n with \020. We have to revert this:
    txt = string.gsub(txt, "\020", "\n")
    txt = string.gsub(txt, "\019", "'")
    txt = string.gsub(txt, "\018", "\\")
    return txt
end

-- TODO: Use or delete
-- local backtick = function(s)
--     local t1 = {}
--     for token in string.gmatch(s, "[^$]+") do
--         table.insert(t1, token)
--     end
--
--     local t3 = {}
--     for _, v in pairs(t1) do
--         local t2 = {}
--         for token in string.gmatch(v, "[^@]+") do
--             if
--                 (not string.find(token, " = $"))
--                 and (
--                     string.find(token, " ")
--                     or string.find(token, "^_")
--                     or string.find(token, "^[0-9]")
--                 )
--             then
--                 table.insert(t2, "`" .. token .. "`")
--             else
--                 table.insert(t2, token)
--             end
--         end
--         table.insert(t3, table.concat(t2, "@"))
--     end
--     return table.concat(t3, "$")
-- end

local get_piped_obj
get_piped_obj = function(line, lnum)
    local l
    l = vim.fn.getline(lnum - 1)
    if type(l) == "string" and string.find(l, "|>%s*$") then
        return get_piped_obj(l, lnum - 1)
    end
    if type(l) == "string" and string.find(l, "%%>%%%s*$") then
        return get_piped_obj(l, lnum - 1)
    end
    if string.find(line, "|>") then return string.match(line, ".-([%w%._]+)%s*|>") end
    if string.find(line, "%%>%%") then
        return string.match(line, ".-([%w%._]+)%s*%%>%%")
    end
    return nil
end

-- TODO: document all functions for lua_ls
local get_first_obj = function(line, lnum)
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
        line = vim.fn.getline(lnum)
    until type(line) == "string" and string.find(line, "^%S") or lnum == 0
    return pkg, funname, firstobj, line, lnum, idx
end

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
    lib, funname, firstobj, nline, nlnum, cnum = get_first_obj(line, lnum)

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

-- FIXME: the whole "resolve" function must be converted to C and put in rnvimserver.c
---@param req_id string
---@param itm_str string
M.resolve = function(req_id, itm_str)
    -- vim.notify(tostring(req_id) .. "\n" .. itm_str)
    local itm = vim.json.decode(itm_str)
    -- vim.notify(tostring(req_id) .. "\n" .. itm_str .. "\n" .. vim.inspect(itm))

    if not itm.cls then return nil end

    -- FIXME: It seems that we don't need this, and this would be only part of the
    -- code that would be difficult do transfer to rnvimserver.
    -- ter = {
    --     start = {
    --         line = lnum + 1,
    --         character = cnum - 1,
    --     },
    --     ["end"] = {
    --         line = lnum + 1,
    --         character = cnum,
    --     },
    -- }

    if itm.env == ".GlobalEnv" then
        if itm.cls == "a" then
            err_msg("RESOLVE A")
        elseif itm.cls == "f" or itm.cls == "b" or itm.cls == "t" or itm.cls == "n" then
            send_to_nvimcom(
                "E",
                string.format(
                    "nvimcom:::nvim.get.summary('%s', '%s', '%s', %s, '%s')",
                    req_id,
                    itm.kind,
                    itm.label,
                    itm.label,
                    itm.env
                )
            )
        elseif itm.cls == "F" then
            send_to_nvimcom(
                "E",
                string.format(
                    "nvimcom:::nvim.GlobalEnv.fun.args('%s', '%s')",
                    req_id,
                    itm.label
                )
            )
        else
            send_to_nvimcom(
                "E",
                string.format(
                    "nvimcom:::nvim.min.info('%s', %s, '%s')",
                    req_id,
                    itm.label,
                    itm.env
                )
            )
        end
        return nil
    end

    -- Column of data.frame for fun_data_1 or fun_data_2
    if itm.cls == "c" then
        send_to_nvimcom(
            "E",
            string.format(
                "nvimcom:::nvim.get.summary('%s', %s$%s, '%s')",
                req_id,
                itm.env,
                itm.label,
                itm.env
            )
        )
    elseif itm.cls == "a" then
        local lbl = itm.label:gsub(" = ", "")
        local pf = vim.fn.split(itm.env, ":")
        M.send_msg(string.format("7%s|%s|%s|%s|%s", req_id, itm.kind, lbl, pf[1], pf[2]))
    elseif itm.cls == "L" then
        itm.documentation = {
            value = fix_doc(itm.env),
            kind = vim.lsp.MarkupKind.Markdown,
        }
        vim.notify("RESOLVE L")
    elseif
        itm.label:find("%$")
        and (itm.cls == "f" or itm.cls == "b" or itm.cls == "t" or itm.cls == "n")
    then
        send_to_nvimcom(
            "E",
            string.format(
                "nvimcom:::nvim.get.summary('%s', %s, '%s')",
                req_id,
                itm.label,
                itm.env
            )
        )
    else
        M.send_msg(string.format("6%s|%s|%s|%s", req_id, itm.kind, itm.label, itm.env))
    end
end

-- TODO: Delete this function
local send_items = function(req_id, tbl)
    local jstr = vim.json.encode(tbl)
    -- Log(jstr)
    vim.notify("CALLBACK [" .. tostring(req_id) .. "]\n" .. jstr)
end

--- Get the word before the cursor, considering that Unicode
--- characters use more bytes than occupy display cells
---@param line string Current line
---@param cnum integer Cursor position in number of display cells
---@param pttrn? string Pattern to get word for completion TODO: delete this argument if not used
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

--- Complete
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
            M.send_msg(string.format("CC%d|%s|", req_id, wrd))
        else
            M.send_msg(string.format("CC%d| |", req_id))
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
                if wrd == "@" then
                    reset_r_compl()
                elseif wrd and wrd:find("^@[tf]") then
                    local lbls = require("r.lsp.figtbl").get_labels(wrd)
                    send_items(req_id, { items = lbls })
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
                if cline:sub(cnum, cnum) == "\\" then M.send_msg("CH" .. req_id) end
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
                M.send_msg(string.format("CB%d|%s|", req_id, wrd))
            else
                M.send_msg(string.format("CB%d| |", req_id))
            end
            return
        end
    end

    if lang ~= "r" then return end

    -- check if the cursor is within comment or string
    local snm = ""
    local c = vim.treesitter.get_captures_at_pos(0, lnum - 1, cnum - 2)
    if #c > 0 then
        for _, v in pairs(c) do
            if v.capture == "string" then
                snm = "rString"
            elseif v.capture == "comment" then
                return
            end
        end
    else
        -- We still need to call synIDattr because there is no treesitter parser for rhelp
        snm = vim.fn.synIDattr(vim.fn.synID(lnum, cnum - 1, 1), "name")
        if snm == "rComment" then return nil end
    end

    -- Should we complete function arguments?
    local nra
    nra = need_R_args(cline:sub(1, cnum), lnum)
    -- TODO: check if need_R_args is working well in all cases
    -- vim.notify(vim.inspect(nra))

    if nra.fnm then
        -- We are passing arguments for a function.
        -- An empty word will be treated as NULL at nvimcom/src/apps/complete.c
        local arg = wrd and wrd or " "

        -- Special completion for library and require
        if
            (nra.fnm == "library" or nra.fnm == "require")
            and (not nra.firstobj or nra.firstobj == arg)
        then
            M.send_msg(string.format("5%s|%s|#| | ", req_id, arg))
            return
        end

        if snm == "rString" then return end

        if vim.g.R_Nvim_status < 7 then
            -- Get the arguments of the first function whose name matches nra.fnm
            if nra.lib then
                M.send_msg(
                    string.format("5%s|%s|%s::%s| | ", req_id, arg, nra.lib, nra.fnm)
                )
            else
                M.send_msg(string.format("5%s|%s|%s| | ", req_id, arg, nra.fnm))
            end
            return
        else
            -- Get arguments according to class of first object
            local msg
            msg = string.format(
                'nvimcom:::nvim_complete_args("%s", "%s", "%s"',
                req_id,
                nra.fnm,
                arg
            )
            if nra.firstobj then
                msg = msg .. ', firstobj = "' .. nra.firstobj .. '"'
            elseif nra.lib then
                msg = msg .. ', lib = "' .. nra.lib .. '"'
            end
            if nra.firstobj and nra.listdf then msg = msg .. ", ldf = TRUE" end
            msg = msg .. ")"

            -- FIXME: Is this correct? Documentation should be during resolve event.
            -- Save documentation of arguments to be used by rnvimserver
            send_to_nvimcom("E", msg)
            return
        end
    end

    if snm == "rString" then return nil end

    if not wrd then
        reset_r_compl()
        return
    end

    M.send_msg(string.format("5%s|%s| | | ", req_id, wrd))
end

--- Execute lua command sent by rnvimserver
local function exe_cmd(_, result, _)
    -- vim.schedule(function() vim.fn.execute("lua " .. result.command) end)
    vim.schedule(function()
        local f = loadstring(result.command)
        if f then f() end
    end)
end

--- Callback invoked when client attaches to a buffer.
---@param client vim.lsp.Client
---@param bnr integer
local function on_attach(client, bnr)
    vim.notify("LSP_on_attach:\n" .. tostring(client) .. "\n" .. tostring(bnr))
end

--- Callback invoked after LSP "initialize"
---@param client vim.lsp.Client
---@param init_res lsp.InitializeResult
local function on_init(client, init_res)
    vim.notify("LSP_on_init:\n" .. tostring(client) .. "\n" .. tostring(init_res))
end

--- Callback invoked on client exit.
---@param code integer Exit code of the process
---@param signal integer Number describing the signal used to terminate (if any)
---@param client integer Client handle
local function on_exit(code, signal, client)
    vim.notify(
        "LSP_on_exit:\n  code: "
            .. vim.inspect(code)
            .. "\n  signal: "
            .. vim.inspect(signal)
            .. "\n  client_id: "
            .. vim.inspect(client)
    )
end

--- Callback invoked when the client operation throws an error.
--- @param code number Number describing the error. See vim.lsp.rpc.client_errors
--- @param err string Error message
local function on_error(code, err)
    vim.notify("LSP_on_error:" .. vim.inspect(code) .. "\n" .. err)
end

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
        trace = "verbose",
        handlers = {
            ["client/exeRnvimCmd"] = exe_cmd,
        },
    })
    -- TODO: enable/disable the language server on CursorMoved event
    -- vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    --     buffer = vim.api.nvim_get_current_buf(),
    --     callback = on_cursor_move,
    -- })
    if client_id then vim.lsp.completion.enable(true, client_id, 0) end
end

function M.send_msg(code)
    local buf = require("r.edit").get_rscript_buf()
    -- lua_ls will warn that "exeRnvimCmd" is not a valid method
    local res = vim.lsp.buf_notify(buf, "exeRnvimCmd", { code = code })
    if not res then warn("Failed to send message to r_ls: " .. code) end
end

return M
