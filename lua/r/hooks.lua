--[[
This module implements functions that manage the execution of
user-defined hooks. These are defined in the `config.hooks` table in
the user configuration:

defaults = {
    ...,
    hook = {
        on_filetype = function() end,
        after_config = function() end,
        after_R_start = function() end,
        after_ob_open = function() end,
    },
    ...,
}

User documentation for user-defined hooks: section 6.29
]]

local M = {}

--- Run the specified user-defined hook
---
--- Currently valid `hook_name` values are 'on_filetype',
--- 'after_config', 'after_R_start', 'after_ob_open'
---
---@param config table
---@param hook_name string
function M.run(config, hook_name)
    if config.hook and config.hook[hook_name] then -- Is config.hook check necessary?
        vim.schedule(function() config.hook[hook_name]() end)
    end
end

return M
