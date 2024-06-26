local M = {}
local S = require("r.send")

local function extract_package_name(message)
    local package_name = message:match("Package '([^']+)'")
    return package_name or "Package name not found"
end

-- Function to format packages as 'c("package1", "package2")'
local function format_packages_list(package_list)
    local formatted_string = 'c("' .. table.concat(package_list, '", "') .. '")'
    return formatted_string
end

M.install_missing_packages = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local diagnostics = vim.diagnostic.get(bufnr)

    if vim.tbl_isempty(diagnostics) then
        print("No diagnostics found under cursor")
        return
    end

    local missing_package_diagnostics = vim.tbl_filter(
        function(diagnostic) return diagnostic.code == "missing_package_linter" end,
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
        .. " are missing. Would you like to install them? (y/n)"
    vim.ui.input({ prompt = msg }, function(input)
        if input == "y" then
            S.cmd(rcmd)
        else
            print("Not installing packages")
        end
    end)
end

return M
