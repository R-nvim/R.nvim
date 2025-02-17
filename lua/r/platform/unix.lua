local M = {}

local uv = vim.uv
local log = require("r.log")
local utils = require("r.utils")
local tmux = require("r.platform.tmux")

function M.configure(config)
    local utime = uv.hrtime()
    if config.R_path ~= "" then
        local rpath = vim.split(config.R_path, ":")
        utils.resolve_fullpaths(rpath)

        -- Add the current directory to the beginning of the path
        table.insert(rpath, 1, "")

        -- loop over rpath in reverse.
        for i = #rpath, 1, -1 do
            local dir = rpath[i]
            local is_dir = uv.fs_stat(dir)
            -- Each element in rpath must exist and be a directory
            if is_dir and is_dir.type == "directory" then
                vim.env.PATH = dir .. ":" .. vim.env.PATH
            else
                log.warn(
                    '"'
                        .. dir
                        .. '" is not a directory. Fix the value of R_path in your config.'
                )
            end
        end
    end

    utils.check_executable(config.R_app, function(exists)
        if not exists then
            log.warn(
                '"'
                    .. config.R_app
                    .. '" not found. Fix the value of either R_path or R_app in your config.'
            )
        end
    end)

    if config.external_term ~= "" then tmux.configure(config) end
    utime = (uv.hrtime() - utime) / 1000000000
    require("r.edit").add_to_debug_info("unix setup", utime, "Time")
end

return M
