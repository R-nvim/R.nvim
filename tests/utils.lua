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

--- Set up a buffer with content and cursor for LSP tests.
--- Returns nil and calls pending() if treesitter parser is unavailable.
---@param content string
---@param cursor_pos number[]
---@return number|nil
local function setup_lsp_test(content, cursor_pos)
    local bufnr = create_r_buffer_from_string(content, "r")
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, cursor_pos)
    vim.treesitter.language.add("r")
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "r")
    if not ok or not parser then
        pending("treesitter parser for R is not available")
        return nil
    end
    parser:parse()
    return bufnr
end

--- Return the last message from a sent_messages list.
---@param sent_messages table
---@return table|nil
local function get_last_message(sent_messages) return sent_messages[#sent_messages] end

return {
    create_r_buffer_from_file = create_r_buffer_from_file,
    create_r_buffer_from_string = create_r_buffer_from_string,
    setup_lsp_test = setup_lsp_test,
    get_last_message = get_last_message,
}
