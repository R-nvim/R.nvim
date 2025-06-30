local kaddr = "?"

local M = {}

M.start = function()
    kaddr = "unix:/tmp/.kitty_Rnvim-"
        .. tostring(vim.fn.localtime()):gsub(".*(...)", "%1")

    local term_cmd = {
        "kitty",
        "--title",
        "R",
        "--instance-group",
        "kitty_sock",
        "-o",
        "allow_remote_control=yes",
        "--listen-on",
        kaddr,
        "-e",
    }

    require("r.term").start(term_cmd, true)
end

--- Send line of command to R Console
---@param command string
---@return boolean
M.send_cmd = function(command)
    local cmd = require("r.term").sanitize(command, true)
    cmd = cmd:gsub("\\", "\\\\")

    local scmd = { "kitten", "@", "send-text", "--to", kaddr, "-m", "id:1", cmd .. "\n" }
    local res = require("r.term").send(scmd)
    return res
end

--- Get kitty socket address
---@return string
M.get_kaddr = function() return kaddr end

return M
