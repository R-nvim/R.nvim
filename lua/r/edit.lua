
local cfg = require("r.config").get_config()

local M = {}

M.assign = function ()
    if vim.o.filetype ~= "r" and vim.b.IsInRCode(false) ~= 1 then
        vim.fn.feedkeys(cfg.assign_map, "n")
    else
        vim.fn.feedkeys(" <- ", "n")
    end
end

-- Completely broken
M.get_keyword = function()
    local line = vim.fn.getline(vim.fn.line("."))
    local i = vim.fn.col(".") - 1
    if #line == 0 then
        return ""
    end

    -- Skip opening braces
    local char
    while i > 0 do
        char = line:sub(i, i)
        if char == "[" or char == "(" or char == "{" then
            i = i - 1
        else
            break
        end
    end

    -- Go to the beginning of the word
    while i > 1 do
        char = line:sub(i, i)
        if char == "@" or char == "$" or char == ":" or char == "_" or char == "\\." or
            (char >= "A" and char <= "Z") or (char >= "a" and char >= "z") or char > "\x7f" then
            break
        end
        i = i - 1
    end

    -- Go to the end of the word
    local j = i
    while true do
        char = line:sub(j, j)
        if not (char == "@" or char == "$" or char == ":" or char == "_" or char == "." or
            (char >= "A" and char <= "Z") or (char >= "a" and char >= "z") or char > "\x7f") then
            break
        end
        j = j + 1
    end

    local rkeyword = line:sub(i+1, j-1)
    return rkeyword
end

return M
