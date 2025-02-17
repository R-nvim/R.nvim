local warn = require("r.log").warn

local M = {}
local S = require("r.send")
local inform = require("r.log").inform

--- Removes duplicate entries from a table of packages.
--- Each package is represented by a table with a 'message' field.
---@param diagnostics table: The table containing package entries.
---@return table: A new table with duplicate packages removed.
-- Lua
local function remove_duplicates(diagnostics)
    local seen_messages = {}
    local unique_diagnostics = {}

    for _, diagnostic in ipairs(diagnostics) do
        if not seen_messages[diagnostic.message] then
            table.insert(unique_diagnostics, diagnostic)
            seen_messages[diagnostic.message] = true
        end
    end

    return unique_diagnostics
end

--- Creates a message prompting the user to install missing packages.
--- The message is pluralized based on the number of missing packages.
---@param missing_packages table: A table containing the names of missing packages.
---@return string: A message indicating the missing packages and asking if they should be installed.
local function create_message(missing_packages)
    local msg
    if #missing_packages == 1 then
        msg = "Package: "
            .. missing_packages[1]
            .. " is missing. Would you like to install it? (y/n): "
    else
        msg = "Packages: "
            .. table.concat(missing_packages, ", ")
            .. " are missing. Would you like to install them? (y/n): "
    end
    return msg
end

---@param message string: The message containing the package name.
---@return string|nil: The extracted package name or a default message if not found.
local function extract_package_name(message)
    if message:find("is not installed") then
        local package_name = message:match("Package '([^']+)'")
        return package_name
    end
    return nil
end

--- Formats a list of package names into a string suitable for R's install.packages function
---@param package_list table: A list of package names to format
---@return string: A formatted string of package names
local function format_packages_list(package_list)
    local formatted_string = 'c("' .. table.concat(package_list, '", "') .. '")'
    return formatted_string
end

--- Installs missing R packages based on diagnostics from the linter
--- Prompts the user for confirmation before proceeding with the installation
M.install_missing_packages = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local diagnostics = vim.diagnostic.get(bufnr)

    local target_codes = {
        ["missing_package_linter"] = true,
        ["namespace_linter"] = true,
    }

    local missing_package_diagnostics = vim.tbl_filter(
        function(diagnostic) return target_codes[diagnostic.code] end,
        diagnostics
    )

    missing_package_diagnostics = remove_duplicates(missing_package_diagnostics)

    local missing_packages = vim.tbl_map(
        function(diagnostic) return extract_package_name(diagnostic.message) end,
        missing_package_diagnostics
    )

    if vim.tbl_isempty(missing_packages) then
        inform("No missing packages found in the current buffer.")
        return
    end

    local formatted_packages_string = format_packages_list(missing_packages)
    local rcmd = "install.packages(" .. formatted_packages_string .. ")"

    local msg = create_message(missing_packages)
    vim.ui.input({ prompt = msg }, function(input)
        if input == "y" then
            S.cmd(rcmd) -- Replace `S.cmd(rcmd)` with your command
        else
            warn("Not installing packages")
        end
    end)
end

return M
