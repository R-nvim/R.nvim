--- Create a new buffer from a file
---@param file_path string
---@return number
local function create_r_buffer_from_file(file_path)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.fn.readfile(file_path))

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

--- Create a new buffer from a string
---@param content string
---@param filetype string
---@return number
local function create_r_buffer_from_string(content, filetype)
    local bufnr = vim.api.nvim_create_buf(false, true)
    local lines = vim.split(content, "\n")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    if filetype then vim.bo[bufnr].filetype = filetype end

    return bufnr
end

return {
    create_r_buffer_from_file = create_r_buffer_from_file,
    create_r_buffer_from_string = create_r_buffer_from_string,
}
