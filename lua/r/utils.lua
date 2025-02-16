local warn = require("r.log").warn
local uv = vim.uv

local M = {}

--- Tries to asynchronously run cmd with --version
--- callback function recieves true if exit code 0, otherwise false
--- false means:
---     1. executable not found.
---     2. Not enough memory to spawn a process.
---     3. User does not have necessary file permissions.
---     4. executable does not support --version flag.
---@param cmd string
---@param callback function
function M.check_executable(cmd, callback)
    uv.spawn(cmd, {
        args = { "--version" }, -- Assuming the executable supports '--version'
        stdio = nil, -- We don't need to capture output here
    }, function(code)
        if code == 0 then
            callback(true)
        else
            callback(false)
        end
    end)
end

--- Get language at current cursor position of rhelp buffer
---@return string
local get_rhelp_lang = function()
    local lastsec = vim.fn.search("^\\\\[a-z][a-z]*{", "bncW")
    local secname = vim.fn.getline(lastsec)
    if
        vim.api.nvim_win_get_cursor(0)[1] > lastsec
        and (
            secname == "\\usage{"
            or secname == "\\examples{"
            or secname == "\\dontshow{"
            or secname == "\\dontrun{"
            or secname == "\\donttest{"
            or secname == "\\testonly{"
        )
    then
        return "r"
    else
        return "rhelp"
    end
end

--- Get language at current cursor position of rnoweb buffer
---@return string
local get_rnw_lang = function()
    local cline = vim.api.nvim_get_current_line()
    if cline:find("^<<.*child *= *") then
        return "chunk_child"
    elseif cline:find("^<<") then
        return "chunk_header"
    elseif cline:find("^@$") then
        return "chunk_end"
    end
    local chunkline = vim.fn.search("^<<", "bncW")
    local docline = vim.fn.search("^@", "bncW")
    if chunkline ~= vim.api.nvim_win_get_cursor(0)[1] and chunkline > docline then
        return "r"
    else
        return "latex"
    end
end

function M.resolve_fullpaths(tbl)
    for i, v in ipairs(tbl) do
        tbl[i] = uv.fs_realpath(v)
    end
end

--- Get language at current cursor position
---@return string
function M.get_lang()
    if vim.bo.filetype == "" then return "none" end
    -- Treesitter for rnoweb always return "latex" or "rnoweb"
    if vim.bo.filetype == "rnoweb" then return get_rnw_lang() end
    -- No treesitter parser for rhelp
    if vim.bo.filetype == "rhelp" then return get_rhelp_lang() end

    local p
    if vim.bo.filetype == "rmd" or vim.bo.filetype == "quarto" then
        local cline = vim.api.nvim_get_current_line()
        if cline:find("^```.*child *= *") then
            return "chunk_child"
        elseif cline:find("^```%{") then
            return "chunk_header"
        elseif cline:find("^```$") then
            return "chunk_end"
        end
        p = vim.treesitter.get_parser(vim.api.nvim_get_current_buf(), "markdown")
    else
        p = vim.treesitter.get_parser()
    end
    local c = vim.api.nvim_win_get_cursor(0)
    local lang = p:language_for_range({ c[1] - 1, c[2], c[1] - 1, c[2] }):lang()
    return lang
end

--- Request the windows manager to focus a window.
--- Currently, has support only for Xorg.
---@param wttl string Part of the window title.
---@param pid number Pid of window application.
M.focus_window = function(wttl, pid)
    local config = require("r.config").get_config()
    if config.has_X_tools then
        vim.system({ "wmctrl", "-a", wttl })
    elseif
        vim.env.XDG_CURRENT_DESKTOP == "sway" or vim.env.XDG_SESSION_DESKTOP == "sway"
    then
        if pid and pid ~= 0 then
            vim.system({ "swaymsg", '[pid="' .. tostring(pid) .. '"]', "focus" })
        elseif wttl then
            vim.system({ "swaymsg", '[name="' .. wttl .. '"]', "focus" })
        end
    end
end

--- Get the directory of the current buffer in Neovim.
-- This function retrieves the path of the current buffer and extracts the directory part.
---@return string The directory path of the current buffer or an empty string if not applicable.
function M.get_R_buffer_directory()
    local buffer_path = vim.api.nvim_buf_get_name(0)

    if buffer_path == "" then
        -- Buffer is not associated with a file.
        return ""
    end

    -- Extract the directory part of the path using Lua's string manipulation
    return buffer_path:match("^(.-)[\\/][^\\/]-$") or ""
end

--- Normalizes a file path by converting backslashes to forward slashes.
-- This function is particularly useful for ensuring file paths are compatible
-- with Windows systems, where backslashes are commonly used as path separators.
---@param path string The file path to normalize.
---@return string The normalized file path with all backslashes replaced by forward slashes.
function M.normalize_windows_path(path) return tostring(path:gsub("\\", "/")) end

--- Ensures that a given directory exists on the file system.
-- If the directory does not exist, it attempts to create it, including any
-- necessary parent directories. This function uses protected call (pcall) to
-- gracefully handle any errors that occur during directory creation, such as
-- permission issues.
---@param dir_path string The path of the directory to check or create.
---@return boolean Returns true if the directory exists or was successfully created.
-- Returns false if an error occurred during directory creation.
function M.ensure_directory_exists(dir_path)
    if vim.fn.isdirectory(dir_path) == 1 then return true end

    -- Using pcall to catch any errors during directory creation
    local status, err = pcall(function() vim.fn.mkdir(dir_path, "p") end)

    -- Check if pcall caught an error
    if not status then
        -- Log the error
        warn("Error creating directory: " .. err)
        -- return false to indicate failure
        return false
    end

    -- Return true to indicate success
    return true
end

local get_fw_info_X = function()
    local obj = vim.system({ "xprop", "-root" }, { text = true }):wait()
    if obj.code ~= 0 then
        warn("Failed to run `xprop -root`")
        return
    end
    local xroot = vim.split(obj.stdout, "\n")
    local awin = nil
    for _, v in pairs(xroot) do
        if v:find("_NET_ACTIVE_WINDOW%(WINDOW%): window id # ") then
            awin = v:gsub("_NET_ACTIVE_WINDOW%(WINDOW%): window id # ", "")
            break
        end
    end
    if not awin then
        warn("Failed to get ID of active window")
        return
    end
    obj = vim.system({ "xprop", "-id", awin }, { text = true }):wait()
    if obj.code ~= 0 then
        warn("xprop is required to get window PID")
        return
    end
    local awinf = vim.split(obj.stdout, "\n")
    local pid = nil
    local nm = nil
    for _, v in pairs(awinf) do
        if v:find("_NET_WM_PID%(CARDINAL%) = ") then
            pid = v:gsub("_NET_WM_PID%(CARDINAL%) = ", "")
        end
        if v:find("WM_NAME%(STRING%) = ") then
            nm = v:gsub("WM_NAME%(STRING%) = ", "")
            nm = nm:gsub('"', "")
        end
    end
    if not pid or not nm then
        warn(
            "Failed to PID or name of active window ("
                .. awin
                .. "): "
                .. tostring(pid)
                .. " "
                .. tostring(nm)
        )
        return
    end
    local config = require("r.config").get_config()
    config.term_title = nm
    config.term_pid = tonumber(pid)
end

local get_fw_info_Sway = function()
    local config = require("r.config").get_config()
    local obj = vim.system({ "swaymsg", "-t", "get_tree" }, { text = true }):wait()
    local t = vim.json.decode(obj.stdout, { luanil = { object = true, array = true } })
    if t and t.nodes then
        for _, v1 in pairs(t.nodes) do
            if #v1 and v1.type == "output" and v1.nodes then
                for _, v2 in pairs(v1.nodes) do
                    if #v2 and v2.type == "workspace" and v2.nodes then
                        for _, v3 in pairs(v2.nodes) do
                            if v3.focused == true then
                                config.term_title = v3.name
                                config.term_pid = v3.pid
                            end
                        end
                    end
                end
            end
        end
    end
end

--- Record PID and name of active window and register them in config.term_pid and
--- config.term_title respectively.
--- This function call the appropriate function for each system.
function M.get_focused_win_info()
    local config = require("r.config").get_config()
    if config.has_X_tools then
        get_fw_info_X()
    elseif
        vim.env.XDG_CURRENT_DESKTOP == "sway" or vim.env.XDG_SESSION_DESKTOP == "sway"
    then
        get_fw_info_Sway()
    end
end

--- Read a Debian Control File (DFC)
--- This format is commonly used in R, e.g. for package DESCRIPTION files,
--- and by RStudio for .Rproj files.
---
--- This implementation is based on the Debian Policy Manual - see
--- https://www.debian.org/doc/debian-policy/ch-controlfields.html for more
--- information.
---
--- Also see ?read.dcf for the R implementation:
--- https://www.rdocumentation.org/packages/base/versions/3.6.2/topics/dcf
---
---@param x string The path to the file to be read
---@return table # A table of dictionaries where each dictionary corresponds
---  to a stanza, and each dictionary key/value to a field name/value
function M.read_dcf(x)
    local lines = vim.fn.readfile(x)

    local stanzas = {}
    local fields = {}
    local cur_field_name = nil
    local cur_field_val = ""

    local has = function(string, pattern) return string:find(pattern) ~= nil end

    -- stylua: ignore start
    local valid_name_chrs = {
        "!", '"', "#", "%$", "%%", "&", "'" ,"%(", "%)", "%*", "%+", ",", "%-",
        "%.", "/",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        ";", "<", "=", ">", "%?", "@",
        "A", "B", "C" , "D" , "E" , "F" , "G", "H" , "I" , "J", "K", "L" , "M",
        "N", "O", "P" , "Q" , "R" , "S" , "T", "U" , "V" , "W", "X", "Y" , "Z",
        "%[", "\\", "%]", "%^", "_", "`",
        "a", "b", "c", "d", "e", "f" , "g" , "h" , "i" , "j" , "k" , "l" , "m",
        "n", "o", "p", "q", "r", "s" , "t" , "u" , "v" , "w" , "x" , "y" , "z",
        "{", "|", "}", "~"
    }
    local name_ptn = "[%" .. vim.fn.join(valid_name_chrs, "") .. "]+"
    local is_valid_name         = function(string) return has(string, "^" .. name_ptn .. "$") end
    local has_colon             = function(string) return has(string, "^[^%:]+:")             end
    local is_continuation       = function(string) return has(string, "^%s+%S")               end
    local is_valid_continuation = function(string) return has(string, "^%s+[^%s#%-]")         end
    local is_newline            = function(string) return has(string, "^%s+%.")               end
    local is_comment            = function(string) return has(string, "^#")                   end
    local is_stanza_separator   = function(string) return has(string, "^%s*$")                end
    local strip_whitespace      = function(string) return string:gsub("^%s+", "")             end
    local split_definition_line = function(string)
        local _, _, name, val = string:find("^([^:]+):%s*(.*)$")
        name = name:gsub("%s+$", "")
        val = val:gsub("%s+$", "")
        return name, val
    end
    -- stylua: ignore end

    local abort = function(msg) error("Malformed file `" .. x .. "`. " .. msg .. "?") end

    local line_spacer = " "

    for i, line in ipairs(lines) do
        if not is_comment(line) then
            -------------------------------------------------------------------
            -- The current line is a stanza separator
            -------------------------------------------------------------------
            if is_stanza_separator(line) then
                if cur_field_name ~= nil then fields[cur_field_name] = cur_field_val end
                if vim.fn.len(fields) > 0 then
                    table.insert(stanzas, fields)
                    fields = {}
                    cur_field_name = nil
                    cur_field_val = ""
                end

            -------------------------------------------------------------------
            -- The current line is a continuation of the previous field
            -------------------------------------------------------------------
            elseif is_continuation(line) then
                if not is_valid_continuation(line) or cur_field_name == nil then
                    abort("check line " .. tostring(i))
                end
                if is_newline(line) then
                    cur_field_val = cur_field_val .. "\n"
                    line_spacer = ""
                else
                    cur_field_val = cur_field_val .. line_spacer .. strip_whitespace(line)
                    line_spacer = " "
                end

            -------------------------------------------------------------------
            -- The current line is the start of a new field
            -------------------------------------------------------------------
            else
                if not has_colon(line) then
                    abort("Possible missing colon on line " .. tostring(i))
                end
                if cur_field_name ~= nil then fields[cur_field_name] = cur_field_val end
                local name, val = split_definition_line(line)
                if not is_valid_name(name) then
                    abort("Possible invalid field name on line " .. tostring(i))
                end
                if vim.fn.len(fields) > 0 and vim.fn.has_key(fields, name) > 0 then
                    abort("Possible duplicate field name on line " .. tostring(i))
                end
                cur_field_name, cur_field_val = name, val
                line_spacer = " "
            end
        end
    end

    if cur_field_name ~= nil then fields[cur_field_name] = cur_field_val end

    if vim.fn.len(fields) > 0 then table.insert(stanzas, fields) end

    return stanzas
end

--- Collapse a table into a human readable string
---
--- E.g:
--- > msg_join({ "foo", "bar", "baz" }, "; ", "; or ", "`")
--- > "`foo`; `bar`; or `baz`"
---
---@param x table A table of strings to collaps
---@param sep? string The separator to use for the collapsed strings
---@param last? string The separator to use between the last 2 strings
---@param quote? string A quote character to use for individual elements
---@return string
function M.msg_join(x, sep, last, quote)
    sep = sep or ", "
    last = last or ", and "
    quote = quote or '"'

    local msg = ""

    for i, v in ipairs(x) do
        local sep_i = sep
        if i == 1 then
            sep_i = ""
        elseif i == #x then
            sep_i = last
        end
        msg = msg .. sep_i .. quote .. v .. quote
    end

    return msg
end

--- Get the root node of the syntax tree for the given buffer.
-- @param bufnr The buffer number (optional).
-- @return The root node of the syntax tree, or nil if no parser is found.
M.get_root_node = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local parser = vim.treesitter.get_parser(bufnr)

    if not parser then return nil end

    local tree = parser:parse()[1]

    return tree:root()
end

---Get the left hand side of a keymap
---@param name  string The `<Plug>` name of the key binding
---@return string|nil
M.get_mapped_key = function(name)
    local ilist = vim.split(vim.fn.execute("imap", "silent!") or "", "\n")
    for _, v in pairs(ilist) do
        if v:find(name .. "$") then
            local km = v:gsub("^i%s*", ""):gsub("%s.*", "")
            return km
        end
    end
    return nil
end

return M
