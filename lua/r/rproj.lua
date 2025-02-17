local read_dcf = require("r.utils").read_dcf
local warn = require("r.log").warn

local M = {}

--- Find a file ending with .Rproj in the same directory, or in an enclosing
--- directory, of the current buffer.
---@return string|nil
function M.find()
    local search_dir = vim.fs.dirname(vim.api.nvim_buf_get_name(0))

    local rproj
    while rproj == nil do
        local prev_dir = search_dir
        rproj = vim.fn.glob(search_dir .. "/*.[Rr]proj", true, true)[1]
        search_dir = vim.fs.dirname(search_dir)
        if search_dir == prev_dir then break end
    end

    return rproj
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
    for _, fields in ipairs(x) do
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
        warn("WARNING: Missing line 'Version: 1.0' in '" .. file .. "'")
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
            elseif val == "Default" or val == "default" then
                -- In this case, the normal R.nvim config will be used
                fields[name] = nil
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

--- Apply configuration from a .Rproj file to R.nvim's config.
---
--- The effect of calling this function is that, when a R.nvim buffer (e.g. an
--- R script) is first opened, certain buffer-specific variables may be set
--- which will reflect the settings in the relevant .Rproj file. These
--- variables can be accessed using vim.api.nvim_buf_get_var(). The advantage
--- of this approach is that a user can jump between R projects that may
--- have different settings and the behaviour of R.nvim will continue to be
--- appropriate for each script.
---
---@param config table I.e. `require("r.config").config`
---@param file? string The .Rproj file to use
---@param force? boolean Apply the .Rproj settings, regardless of
---  require("r.config").config.rproj_prioritise
function M.apply_settings(config, file, force)
    local fields = M.parse(file)
    if not fields then return end
    if not config.rproj_prioritise then return end

    local to_update = function(x) return vim.fn.index(config.rproj_prioritise, x) >= 0 end

    for name, val in pairs(fields) do
        if name == "UseNativePipeOperator" and (to_update("pipe_version") or force) then
            if val then
                vim.api.nvim_buf_set_var(0, "rnvim_pipe_version", "native")
            else
                vim.api.nvim_buf_set_var(0, "rnvim_pipe_version", "magrittr")
            end
        end
    end
end

return M
