local read_dcf = require("r.utils").read_dcf
local warn = require("r.init").warn

local M = {}

--- Find a file ending with .Rproj in the current directory
---@return string|nil
function M.find()
    -- Supposedly `*` will match 0 chars... In practice doesn't seem to be true,
    -- so need to check for that case manually
    local x = vim.fn.glob("*.[Rr]proj", true, true)
    local y = vim.fn.glob(".[Rr]proj", true, true)
    table.move(y, 1, #y, #x + 1, x)
    return x[1]
end

--- Combine a table of dictionaries into a single dictionary.
---
--- Assumes there are no duplicates; keeps the last occurrance if there are.
--- In practice, duplicates will only occur if there are issues with the input
--- .Rproj file.
---
---@param x table A table of dictionaries (i.e. results of read_dcf())
---@return table
local squash_dcf_results = function(x)
    local out = {}
    for stanza, fields in ipairs(x) do
        for name, val in pairs(fields) do
            out[name] = val
        end
    end
    return out
end

--- Parse a .Rproj file into a dictionary of configuration settings
---
---@param file? string The name of the file to read. If omitted, the file will
---  be searched for in the current directory.
---@return table|nil
function M.parse(file)
    file = file or M.find()
    if not file then return end

    local file_ok, contents = pcall(read_dcf, file)

    if not file_ok then
        ---@diagnostic disable-next-line: param-type-mismatch
        warn("WARNING: " .. contents)
        return
    end

    local fields = squash_dcf_results(contents)

    -- RStudio will give an error if this is not present. It's worth checking
    -- it is, because people who only use R.nvim might forget otherwise.
    -- NB, there are other fields that RStudio will add automatically, but
    -- this is the only one it will complain about if not present.
    if not vim.fn.has_key(fields, "Version") and fields.Version == "1.0" then
        warn("WARNING: Missing line 'Version: 1.0' in " .. file .. "'")
    end

    -- Fields that, if they exist, should either be 'Yes' or 'No'
    local expected_boolean_fields = {
        RestoreWorkspace = true,
        SaveWorkspace = true,
        AlwaysSaveHistory = true,
        UseSpacesForTab = true,
        AutoAppendNewline = true,
        PackageUseDevtools = true,
        StripTrailingWhitespace = true,
        UseNativePipeOperator = true,
    }

    -- stylua: ignore start
    for name, val in pairs(fields) do
        if expected_boolean_fields[name] then
            if val == "Yes" or val == "yes" then
                fields[name] = true
            elseif val == "No" or val == "no" then
                fields[name] = false
            else
                warn(
                    "WARNING: Unexpected configuration in "
                        .. file .. " `" .. name .. " = " .. val .. "`; "
                        .. "expected either 'Yes' or 'No'."
                )
                fields[name] = nil
            end
        end
    end
    -- stylua: ignore end

    return fields
end

--- Apply configuration from a .Rproj file to R.nvim's config
---
--- Currently only does anything with 'UseNativePipeOperator'
---
---@param config table I.e. `require("r.config").config`
---@param force? boolean Apply the .Rproj settings, regardless of
---  require("r.config").config.rproj_prioritise
---@param file? string The .Rproj file to use
function M.apply_settings(config, force, file)
    local fields = M.parse(file)
    if not fields then return end
    if not config.rproj_prioritise then return end

    local to_update = function(x)
        for i, val in ipairs(config.rproj_prioritise) do
            if val == x then return true end
        end
        return false
    end

    for name, val in pairs(fields) do
        if
            name == "UseNativePipeOperator" and (to_update("use_native_pipe") or force)
        then
            config.use_native_pipe = val
        end
    end
end

return M
