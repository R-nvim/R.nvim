local M = {}
local S = require("r.send")

---@param message string: The message containing the package name.
---@return string: The extracted package name or a default message if not found.
local function extract_package_name(message)
    local package_name = message:match("Package '([^']+)'")
    return package_name or "Package name not found"
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

    if vim.tbl_isempty(diagnostics) then
        print("No diagnostics found under cursor")
        return
    end

    local target_codes = {
        ["missing_package_linter"] = true,
        ["namespace_linter"] = true,
    }

    local missing_package_diagnostics = vim.tbl_filter(
        function(diagnostic) return target_codes[diagnostic.code] end,
        diagnostics
    )

    local missing_packages = vim.tbl_map(
        function(diagnostic) return extract_package_name(diagnostic.message) end,
        missing_package_diagnostics
    )

    if vim.tbl_isempty(missing_packages) then return end

    local formatted_packages_string = format_packages_list(missing_packages)
    local rcmd = "install.packages(" .. formatted_packages_string .. ")"

    local msg = "Packages: "
        .. table.concat(missing_packages, ", ")
        .. " are missing. Would you like to install them? (y/n): "
    vim.ui.input({ prompt = msg }, function(input)
        if input == "y" then
            S.cmd(rcmd)
        else
            print("\nNot installing packages")
        end
    end)
end

return M
