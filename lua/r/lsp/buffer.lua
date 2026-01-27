--- Buffer management for LSP operations
--- Handles temporary buffer creation for parsing external files
--- and ensures proper cleanup
---@module 'r.lsp.buffer'

local M = {}

--- Create temporary buffer for parsing with automatic cleanup
---@param content string|string[] File content (string or lines)
---@param filetype? string Filetype to set (default "r")
---@return integer bufnr, function cleanup
function M.create_temp_buffer(content, filetype)
    filetype = filetype or "r"

    local bufnr = vim.api.nvim_create_buf(false, true)

    if type(content) == "string" then content = vim.split(content, "\n") end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
    vim.api.nvim_set_option_value("filetype", filetype, { buf = bufnr })

    local cleanup = function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end

    return bufnr, cleanup
end

--- Parse file and create temp buffer
---@param filepath string Path to file
---@return integer? bufnr, string? content, function? cleanup
function M.load_file_to_buffer(filepath)
    local file = io.open(filepath, "r")
    if not file then return nil, nil, nil end

    local content = file:read("*all")
    file:close()

    if not content or content == "" then return nil, nil, nil end

    local bufnr, cleanup = M.create_temp_buffer(content, "r")
    return bufnr, content, cleanup
end

--- Get or create buffer from filepath
--- If file is already loaded, returns existing buffer
--- Otherwise creates temporary buffer
---@param filepath string Path to file
---@return integer? bufnr, boolean is_temp
function M.get_or_create_buffer(filepath)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            local buf_name = vim.api.nvim_buf_get_name(buf)
            if buf_name == filepath then return buf, false end
        end
    end

    local bufnr, _, _ = M.load_file_to_buffer(filepath)
    if not bufnr then return nil, false end

    return bufnr, true
end

return M
