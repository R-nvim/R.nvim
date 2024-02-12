local config = require("r.config").get_config()
local warn = require("r").warn

-- Check if the cursor is in the Examples section of R documentation
---@param vrb boolean
---@return boolean
local is_in_R_code = function(vrb)
    local exline = vim.fn.search("^Examples:$", "bncW")
    if exline > 0 and vim.fn.line(".") > exline then
        return true
    else
        if vrb then warn('Not in the "Examples" section.') end
        return false
    end
end

local M = {}

M.set_buf_options = function()
    vim.api.nvim_buf_set_var(0, "IsInRCode", is_in_R_code)
    vim.api.nvim_set_option_value("number", false, { scope = "local" })
    vim.api.nvim_set_option_value("swapfile", false, { scope = "local" })
    vim.api.nvim_set_option_value("syntax", "rdoc", { scope = "local" })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { scope = "local" })
    vim.api.nvim_set_option_value("buftype", "nofile", { scope = "local" })
    vim.api.nvim_set_option_value("iskeyword", "@,48-57,_,.", { scope = "local" })

    require("r.config").real_setup()
    require("r.maps").create("rdoc")
end

-- Prepare R documentation output to be displayed by Nvim
M.fix_rdoc = function(txt)
    txt = string.gsub(txt, "%_\008", "")
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
    local n = 1
    local N = #lines
    while n < N do
        -- Add a tab character before each section to mark its end.
        if lines[n]:match("^[A-Z][a-z]+:") then lines[n - 1] = lines[n - 1] .. "\t" end
        n = n + 1
    end
    return lines
end

-- Move the cursor to the Examples section in R documentation
M.go_to_ex_section = function()
    local ii = vim.fn.search("^Examples:$", "nW")
    if ii == 0 then
        warn("No example section below.")
    else
        vim.fn.cursor(ii + 1, 1)
    end
end

return M
