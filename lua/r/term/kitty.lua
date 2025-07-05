local config = require("r.config").get_config()

local kname = nil
local r_wid = "1"

local M = {}

M.start = function()
    kname = "unix:/tmp/.kitty_Rnvim-"
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
        kname,
    }
    local wd = require("r.run").get_R_start_dir()
    if wd then table.insert(term_cmd, "--directory='" .. wd .. "'") end
    table.insert(term_cmd, "-e")

    local rargs = require("r.run").get_r_args()
    if rargs == "" then
        table.insert(term_cmd, config.R_app)
    else
        local rcmd = config.R_app .. " " .. rargs
        local rcmdls = vim.fn.split(rcmd, " ")
        for _, v in pairs(rcmdls) do
            table.insert(term_cmd, v)
        end
    end

    require("r.term").start(term_cmd)
end

--- Send line of command to R Console
---@param command string
---@return boolean
M.send_cmd = function(command)
    local cmd = require("r.term").sanitize(command, true)
    cmd = cmd:gsub("\\", "\\\\")

    local scmd =
        { "kitten", "@", "send-text", "--to", kname, "-m", "id:" .. r_wid, cmd .. "\n" }
    local res = require("r.term").send(scmd)
    return res
end

return M
