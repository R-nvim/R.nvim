-- Ensure the R parser is installed
local parsers = require("nvim-treesitter.parsers")
local parser_config = parsers.get_parser_configs()
assert(parser_config.r, "R parser is not installed")

-- Function to create a buffer with R code from a file
local function create_r_buffer_from_file(file_path)
    -- Read the file content
    local r_code = table.concat(vim.fn.readfile(file_path), "\n")

    -- Trim spaces from lines
    local trimmed_lines = {}
    for line in r_code:gmatch("[^\n]+") do
        table.insert(trimmed_lines, line:match("^%s*(.-)%s*$"))
    end

    -- Create buffer, set lines, and configure filetype
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, trimmed_lines)

    local ext = string.lower(vim.fn.fnamemodify(file_path, ":e"))

    if ext == "r" then
        vim.bo[bufnr].filetype = "r"
    elseif ext == "rmd" then
        vim.bo[bufnr].filetype = "rmd"
    elseif ext == "qmd" then
        vim.bo[bufnr].filetype = "quarto"
    end

    return bufnr
end

return {
    create_r_buffer_from_file = create_r_buffer_from_file,
}
