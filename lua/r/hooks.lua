--[[
This module implements functions that manage the execution of
user-defined hooks. These are defined in the `config.hooks` table in
the user configuration.
]]

local M = {}

--- Run the specified user-defined hook
---@param config table
---@param hook_name string
---@param schdl boolean
function M.run(config, hook_name, schdl)
    if config.hook[hook_name] then
        if schdl then
            vim.schedule(config.hook[hook_name])
        else
            config.hook[hook_name]()
        end
    end
end

return M
