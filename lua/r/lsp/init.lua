local send_to_nvimcom = require("r.run").send_to_nvimcom

local r_ls = {
    initialized = false,
    stopped = true,
}

local last_compl_item
local cb_cmp
local cb_rsv
local compl_id = 0
-- local ter = nil
local qcell_opts = nil
local chunk_opts = nil
local rhelp_keys = nil
local compl_region = true

local options = {
    doc_width = 58,
    trigger_characters = { " ", ":", "(", '"', "@", "$" },
    fun_data_1 = { "select", "rename", "mutate", "filter" },
    fun_data_2 = { ggplot = { "aes" }, with = { "*" } },
    quarto_intel = nil,
}

-- Translate symbols added by nvimcom to LSP kinds
local kindtbl = {
    ["("] = vim.lsp.protocol.CompletionItemKind.Function, -- function
    ["$"] = vim.lsp.protocol.CompletionItemKind.Struct, -- data.frame
    ["%"] = vim.lsp.protocol.CompletionItemKind.Method, -- logical
    ["~"] = vim.lsp.protocol.CompletionItemKind.Text, -- character
    ["{"] = vim.lsp.protocol.CompletionItemKind.Value, -- numeric
    ["!"] = vim.lsp.protocol.CompletionItemKind.Field, -- factor
    [";"] = vim.lsp.protocol.CompletionItemKind.Constructor, -- control
    ["["] = vim.lsp.protocol.CompletionItemKind.Struct, -- list
    ["<"] = vim.lsp.protocol.CompletionItemKind.Class, -- S4
    [">"] = vim.lsp.protocol.CompletionItemKind.Class, -- S7
    [":"] = vim.lsp.protocol.CompletionItemKind.Interface, -- environment
    ["&"] = vim.lsp.protocol.CompletionItemKind.Event, -- promise
    ["l"] = vim.lsp.protocol.CompletionItemKind.Module, -- library
    ["a"] = vim.lsp.protocol.CompletionItemKind.Variable, -- function argument
    ["c"] = vim.lsp.protocol.CompletionItemKind.Field, -- data.frame column
    ["*"] = vim.lsp.protocol.CompletionItemKind.TypeParameter, -- other
}

local send_to_nrs = function(msg)
    if vim.g.R_Nvim_status and vim.g.R_Nvim_status > 2 then
        require("r.job").stdin("Server", msg)
    end
end

local fix_doc = function(txt)
    -- The rnvimserver replaces ' with \019 and \n with \020. We have to revert this:
    txt = string.gsub(txt, "\020", "\n")
    txt = string.gsub(txt, "\019", "'")
    txt = string.gsub(txt, "\018", "\\")
    return txt
end

local backtick = function(s)
    local t1 = {}
    for token in string.gmatch(s, "[^$]+") do
        table.insert(t1, token)
    end

    local t3 = {}
    for _, v in pairs(t1) do
        local t2 = {}
        for token in string.gmatch(v, "[^@]+") do
            if
                (not string.find(token, " = $"))
                and (
                    string.find(token, " ")
                    or string.find(token, "^_")
                    or string.find(token, "^[0-9]")
                )
            then
                table.insert(t2, "`" .. token .. "`")
            else
                table.insert(t2, token)
            end
        end
        table.insert(t3, table.concat(t2, "@"))
    end
    return table.concat(t3, "$")
end

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

    -- Check if this is function for which we expect to complete data frame column names
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

local reset_r_compl = function()
    -- for _, v in pairs(cmp.core.sources or {}) do
    --     if v.name == "cmp_r" then
    --         v:reset()
    --         break
    --     end
    -- end
    vim.notify("NOT IMPLEMENTED: reset_r_compl")
end

local resolve = function(itm, callback)
    -- itm = params = {
    --     kind = 6,
    --     label = "Henrich (2016) The secret of our success: how culture is d⋯",
    --     textEdit = {
    --         newText = "DHA5RLLS-Henrich-2016",
    --         range = {
    --             ["end"] = { character = 2, line = 9 },
    --             start = { character = 1, line = 9 }
    --         },
    --     },
    -- }

    cb_rsv = callback
    last_compl_item = itm

    if not itm.cls then
        callback(itm)
        return nil
    end

    if itm.env == ".GlobalEnv" then
        if itm.cls == "a" then
            callback(itm)
        elseif itm.cls == "!" or itm.cls == "%" or itm.cls == "~" or itm.cls == "{" then
            send_to_nvimcom(
                "E",
                "nvimcom:::nvim.get.summary(" .. itm.label .. ", '" .. itm.env .. "')"
            )
        elseif itm.cls == "(" then
            send_to_nvimcom(
                "E",
                'nvimcom:::nvim.GlobalEnv.fun.args("' .. itm.label .. '")'
            )
        else
            send_to_nvimcom(
                "E",
                "nvimcom:::nvim.min.info(" .. itm.label .. ", '" .. itm.env .. "')"
            )
        end
        return nil
    end

    -- Column of data.frame for fun_data_1 or fun_data_2
    if itm.cls == "c" then
        send_to_nvimcom(
            "E",
            "nvimcom:::nvim.get.summary("
                .. itm.env
                .. "$"
                .. itm.label
                .. ", '"
                .. itm.env
                .. "')"
        )
    elseif itm.cls == "a" then
        local i = itm.label:gsub(" = ", "")
        local pf = vim.fn.split(itm.env, "\002")
        send_to_nrs("7" .. pf[1] .. "\002" .. pf[2] .. "\002" .. i .. "\n")
    elseif itm.cls == "l" then
        itm.documentation = {
            value = fix_doc(itm.env),
            kind = vim.lsp.MarkupKind.Markdown,
        }
        callback(itm)
    elseif
        itm.label:find("%$")
        and (itm.cls == "!" or itm.cls == "%" or itm.cls == "~" or itm.cls == "{")
    then
        send_to_nvimcom(
            "E",
            "nvimcom:::nvim.get.summary(" .. itm.label .. ", '" .. itm.env .. "')"
        )
    else
        send_to_nrs("6" .. itm.label .. "\002" .. itm.env .. "\n")
    end
end

local complete = function(params, callback)
    -- params = {
    --     context = {
    --         triggerKind = 1
    --     },
    --     position = {
    --         character = 2,
    --         line = 9
    --     },
    --     textDocument = {
    --         uri = "file:///home/aquino/src/issues/test.md"
    --     }
    -- }
    if not compl_region then return end
    if vim.g.R_Nvim_status < 3 then return end
    cb_cmp = callback
    local cnum = params.position.character
    local lnum = params.position.line
    -- In cmp-r: cline = request.context.cursor_before_line
    local cline = vim.api.nvim_buf_get_lines(0, lnum, lnum + 1, true)[1]

    -- Check if this is Rmd and the cursor is in the chunk header
    if vim.bo.filetype == "rmd" and cline:find("^```{r") then
        if not chunk_opts then chunk_opts = require("r.lsp.chunk").get_opts() end
        callback({ items = chunk_opts })
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
                local wrd = cline:sub(cnum)
                if wrd == "@" then
                    reset_r_compl()
                elseif wrd:find("^@[tf]") then
                    local lbls = require("r.lsp.figtbl").get_labels(wrd)
                    callback({ items = lbls })
                end
                return {}
            end
        elseif vim.bo.filetype == "rnoweb" then
            for i = lnum, 1, -1 do
                if string.find(lines[i], "^%s*<<.*>>=") then
                    lang = "r"
                    break
                elseif string.find(lines[i], "^@") then
                    return {}
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
                local wrd = cline:sub(cnum)
                if #wrd == 0 then
                    reset_r_compl()
                    return nil
                end
                if wrd == "\\" then
                    if not rhelp_keys then
                        rhelp_keys = require("r.lsp.rhelp").get_keys()
                    end
                    callback({ items = rhelp_keys })
                    return
                end
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
            callback({ items = qcell_opts })
            return
        end
    end

    if lang ~= "r" then return {} end

    -- check if the cursor is within comment or string
    local snm = ""
    local c = vim.treesitter.get_captures_at_pos(0, lnum - 1, cnum - 2)
    if #c > 0 then
        for _, v in pairs(c) do
            if v.capture == "string" then
                snm = "rString"
            elseif v.capture == "comment" then
                return nil
            end
        end
    else
        -- We still need to call synIDattr because there is no treesitter parser for rhelp
        snm = vim.fn.synIDattr(vim.fn.synID(lnum, cnum - 1, 1), "name")
        if snm == "rComment" then return nil end
    end

    -- required by rnvimserver
    compl_id = compl_id + 1

    local wrd = cline:sub(cnum)
    wrd = string.gsub(wrd, "`", "")
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

    -- Should we complete function arguments?
    local nra
    nra = need_R_args(cline, lnum)

    if nra.fnm then
        -- We are passing arguments for a function

        -- Special completion for library and require
        if
            (nra.fnm == "library" or nra.fnm == "require")
            and (not nra.firstobj or nra.firstobj == wrd)
        then
            send_to_nrs("5" .. compl_id .. "\003\004" .. wrd .. "\n")
            return nil
        end

        if snm == "rString" then return nil end

        if vim.g.R_Nvim_status < 7 then
            -- Get the arguments of the first function whose name matches nra.fnm
            if nra.lib then
                send_to_nrs(
                    "5"
                        .. compl_id
                        .. "\003\005"
                        .. wrd
                        .. "\005"
                        .. nra.lib
                        .. "::"
                        .. nra.fnm
                        .. "\n"
                )
            else
                send_to_nrs(
                    "5" .. compl_id .. "\003\005" .. wrd .. "\005" .. nra.fnm .. "\n"
                )
            end
            return nil
        else
            -- Get arguments according to class of first object
            local msg
            msg = 'nvimcom:::nvim_complete_args("'
                .. compl_id
                .. '", "'
                .. nra.fnm
                .. '", "'
                .. wrd
                .. '"'
            if nra.firstobj then
                msg = msg .. ', firstobj = "' .. nra.firstobj .. '"'
            elseif nra.lib then
                msg = msg .. ', lib = "' .. nra.lib .. '"'
            end
            if nra.firstobj and nra.listdf then msg = msg .. ", ldf = TRUE" end
            msg = msg .. ")"

            -- Save documentation of arguments to be used by rnvimserver
            send_to_nvimcom("E", msg)
            return nil
        end
    end

    if snm == "rString" then return nil end

    if #wrd == 0 then
        reset_r_compl()
        return nil
    end

    send_to_nrs("5" .. compl_id .. "\003" .. wrd .. "\n")

    return nil
end

--- Hover implementation
local hover = function(lnum, cnum)
    vim.notify(string.format("HOVER not implemented: [%d, %d]", lnum, cnum))
end

--- This function receives 4 arguments: method, params, callback, notify_callback
local function lsp_request(method, params, callback, notify_callback)
    if method == "textDocument/completion" then
        complete(params, callback)
    elseif method == "completionItem/resolve" then
        resolve(params, callback)
    elseif method == "textDocument/hover" then
        if not compl_region then return end
        local res = hover(params.position.line, params.position.character)
        if res then callback(nil, res) end
    elseif method == "initialize" then
        local serverCapabilities = {
            capabilities = {
                textDocument = {
                    completion = {
                        completionItem = {
                            resolveSupport = {
                                properties = {
                                    "documentation",
                                    "detail",
                                    "additionalTextEdits",
                                },
                            },
                        },
                    },
                },
                hoverProvider = true,
                completionProvider = {
                    resolveProvider = true,
                    triggerCharacters = options.trigger_characters,
                },
            },
        }
        callback(nil, serverCapabilities)
    else
        vim.notify(
            string.format(
                "REQUEST\nmethod: %s\nparams: %s\ncallback: %s\nnotify_callback: %s",
                vim.inspect(method),
                vim.inspect(params),
                vim.inspect(callback),
                vim.inspect(notify_callback)
            )
        )
    end
end

--- This function receives two arguments: method, params
local function lsp_notify(method, _)
    if method == "initialized" then
        r_ls.initialized = true
        r_ls.stopped = false
    end
end

-- Ver ~/.local/share/nvim/site/pack/core/opt/none-ls.nvim/lua/null-ls/rpc.lua
local function lsp_start(_, _)
    return {
        request = lsp_request,
        notify = lsp_notify,
        is_closing = function() return r_ls.stopped end,
        terminate = function() r_ls.stopped = true end,
    }
end

local M = {}

function M.start()
    -- TODO: remove this when nvim 0.12 is released
    if not vim.lsp.config then return end

    vim.lsp.config("r_ls", {})
    vim.lsp.start({ name = "r_ls", cmd = lsp_start })
    -- vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    --     buffer = vim.api.nvim_get_current_buf(),
    --     callback = on_cursor_move,
    -- })
end

---Callback function for the "resolve" method. When we doesn't have the necessary
---data for resolving the completion (which happens in most cases), we request
---the data to rnvimserver which calls back this function.
---@param txt string The text almost ready to be displayed.
M.resolve_cb = function(txt)
    local s = fix_doc(txt)
    if last_compl_item.def then
        s = last_compl_item.label .. fix_doc(last_compl_item.def) .. "\n---\n" .. s
    end
    last_compl_item.documentation = { kind = "markdown", value = s }
    cb_rsv(nil, last_compl_item)
end

---Callback function for the "complete" method. When we doesn't have the
---necessary data for completion (which happens in most cases), we request the
---completion data to rnvimserver which calls back this function.
---@param cid number The completion ID.
---@param compl table The completion data.
M.complete_cb = function(cid, compl)
    if cid ~= compl_id then return nil end
    -- vim.notify(vim.inspect(ter))

    local resp = {}
    for _, v in pairs(compl) do
        local lbl = v.label:gsub("\019", "'")
        local k = kindtbl[v.cls]
        table.insert(resp, {
            label = lbl,
            env = v.env,
            cls = v.cls,
            def = v.def or nil,
            kind = k,
            -- sortText = v.cls == "a" and "0" or "9",
            insertText = backtick(lbl),
            -- textEdit = { newText = backtick(lbl), range = ter },
        })
    end
    cb_cmp(nil, {
        isIncomplete = false,
        is_incomplete_forward = false,
        is_incomplete_backward = true,
        items = resp,
    })
end

return M
