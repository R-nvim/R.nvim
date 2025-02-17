local M = {}
local uv = vim.uv
local log = require("r.log")

function M.configure(config)
    local ttime = uv.hrtime()
    -- Check whether Tmux is OK
    if vim.fn.executable("tmux") == 0 then
        config.external_term = ""
        log.warn("tmux executable not found")
        return
    end

    local tmuxversion
    if config.uname:find("OpenBSD") then
        -- Tmux does not have -V option on OpenBSD: https://github.com/jcfaria/Vim-R-plugin/issues/200
        tmuxversion = "0.0"
    else
        local obj = vim.system({ "tmux", "-V" }, { text = true }):wait()
        tmuxversion = obj.stdout:gsub(".* ([0-9]%.[0-9]).*", "%1")
        if tmuxversion ~= "" then
            if #tmuxversion ~= 3 then tmuxversion = "1.0" end
            if tmuxversion < "3.0" then log.warn("R.nvim requires Tmux >= 3.0") end
        end
    end
    ttime = (uv.hrtime() - ttime) / 1000000000
    require("r.edit").add_to_debug_info("tmux setup", ttime, "Time")
end

return M
