local config = require("r.config").get_config()
local warn = require("r").warn

local M = {}

-- Check if the cursor is in the Examples section of R documentation
---@param vrb boolean
---@return boolean
M.is_in_R_code = function(vrb)
    local exline = vim.fn.search("^Examples:$", "bncW")
    if exline > 0 and vim.api.nvim_win_get_cursor(0)[1] > exline then
        return true
    else
        if vrb then warn('Not in the "Examples" section.') end
        return false
    end
end

M.set_buf_options = function()
    if vim.o.filetype ~= "" then
        -- The buffer was previously used to display an R object.
        vim.api.nvim_set_option_value("filetype", "", { scope = "local" })
    end
    vim.api.nvim_buf_set_var(0, "IsInRCode", M.is_in_R_code)
    vim.api.nvim_set_option_value("number", false, { scope = "local" })
    vim.api.nvim_set_option_value("swapfile", false, { scope = "local" })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { scope = "local" })
    vim.api.nvim_set_option_value("buftype", "nofile", { scope = "local" })
    vim.api.nvim_set_option_value("iskeyword", "@,48-57,_,.", { scope = "local" })
    vim.api.nvim_set_option_value("signcolumn", "no", { scope = "local" })
    vim.api.nvim_set_option_value("foldcolumn", "0", { scope = "local" })
    if vim.bo.syntax ~= "rdoc" then
        vim.api.nvim_set_option_value("syntax", "rdoc", { scope = "local" })
    end

    require("r.config").real_setup()
    require("r.maps").create("rdoc")
end

---Prepare R documentation output to be displayed by Nvim
---@param txt string
---@return string[]
M.fix_rdoc = function(txt)
    txt = string.gsub(txt, "%_\008", "")
    txt = string.gsub(txt, "\019", "'")
    txt = string.gsub(txt, "\018", "\\")
    txt = string.gsub(txt, "<URL: %([^>]*%)>", " |%1|")
    txt = string.gsub(txt, "<email: %([^>]*%)>", " |%1|")
    if not config.is_windows then
        -- curly single quotes only if the environment is UTF-8
        txt = string.gsub(txt, "\145", "‘")
        txt = string.gsub(txt, "\146", "’")
    end

    -- Mark the end of Examples
    if txt:find("\020Examples:\020") then txt = txt .. "\020###" end

    local lines = vim.split(txt, "\020")
    local i = 1
    local j = #lines
    while i < j do
        if lines[i]:match("^[A-Z][a-z]+:") then
            -- Add a tab character before each section to mark its end.
            lines[i - 1] = lines[i - 1] .. "\t"
            -- Add an empty space to make the highlighting of the first argument work
            if lines[i] == "Arguments:" then lines[i] = "Arguments: " end
        end
        i = i + 1
    end
    return lines
end

-- Move the cursor to the Examples section in R documentation
M.go_to_ex_section = function()
    local i = vim.fn.search("^Examples:$", "nW")
    if i == 0 then
        warn("No example section below.")
    else
        vim.api.nvim_win_set_cursor(0, { i, 0 })
    end
end

return M
