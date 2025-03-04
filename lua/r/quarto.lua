local M = {}

local Chunk = {}
Chunk.__index = Chunk

--- Constructor for the Chunk class
---@param content string The content of the code chunk.
---@param start_row integer The starting row of the code chunk.
---@param end_row integer The ending row of the code chunk.
---@param info_string_params table The parameters specified in the info string of the code chunk.
---@param comment_params table The parameters specified in the code chunk with #|
---@param lang string The language of the code chunk.
---@return table
function Chunk:new(content, start_row, end_row, info_string_params, comment_params, lang)
    local chunk = {
        content = content,
        start_row = start_row,
        end_row = end_row,
        info_string_params = info_string_params,
        comment_params = comment_params,
        lang = lang,
    }

    setmetatable(chunk, Chunk)

    return chunk
end

function Chunk:range() return self.start_row, self.end_row end

M.command = function(what)
    local config = require("r.config").get_config()
    local send_cmd = require("r.send").cmd
    if what == "stop" then
        send_cmd("quarto::quarto_preview_stop()")
        return
    end

    vim.cmd("update")
    local qa = what == "render" and config.quarto_render_args
        or config.quarto_preview_args
    local cmd = "quarto::quarto_"
        .. what
        .. '("'
        .. vim.fn.expand("%"):gsub("\\", "/")
        .. '"'
        .. qa
        .. ")"
    send_cmd(cmd)
end

--- Helper function to get code block from Rmd or Quarto document
---@param bufnr  integer The buffer number.
---@return table|nil
local get_code_chunks = function(bufnr)
    local root = require("r.utils").get_root_node()
    if not root then return nil end

    local query = vim.treesitter.query.parse(
        "markdown",
        [[
                (fenced_code_block
                    (info_string (language) @lang) @info_string
                    (#match? @info_string "^\\{.*\\}$")
                    (code_fence_content) @content) @fenced_code_block
            ]]
    )

    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local code_chunks = {}

    for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
        local capture_name = query.captures[id]

        if capture_name == "content" then
            local lang
            local info_string_params = {}
            local start_row, _, end_row, _ = node:range()

            -- Get the info string of the code block and parse it
            local parent = node:parent()
            if parent then
                local info_node = parent:child(1)
                if info_node and info_node:type() == "info_string" then
                    local info_string = vim.treesitter.get_node_text(info_node, bufnr)
                    lang, info_string_params = M.parse_info_string_params(info_string)
                end
            end

            -- Get the parameters specified in the code chunk with #|
            local comment_params =
                M.parse_comment_params(vim.treesitter.get_node_text(node, bufnr))

            local chunk = Chunk:new(
                vim.treesitter.get_node_text(node, bufnr),
                start_row,
                end_row,
                info_string_params,
                comment_params,
                lang
            )

            table.insert(code_chunks, chunk)
        end
    end

    return code_chunks
end

--- Helper function to parse the info string of a code block
---@param info_string string The info string of the code block.
---@return string,table
M.parse_info_string_params = function(info_string)
    local params = {}

    if info_string == nil then return "", params end

    local lang = info_string:match("^%s*{?([^%s,{}]+)")
    if lang == nil then return "", params end

    local param_str = info_string:sub(#lang + 1):gsub("[{}]", "") -- Remove { and }
    local param_list = vim.split(param_str, ",")
    for _, param in ipairs(param_list) do
        local key, value = param:match("^%s*([^=]+)%s*=%s*([^%s]+)%s*$")

        if key and value then
            key = key:match("^%s*(.-)%s*$") -- Trim leading/trailing spaces from key
            value = value:match("^%s*(.-)%s*$") -- Trim leading/trailing spaces from value
            params[key] = value
        end
    end

    return lang, params
end

--- Helper function to parse the parameters specified in the code chunk with #|
---@param code_content string The content of the code chunk.
---@return table
M.parse_comment_params = function(code_content)
    local params = {}

    for line in code_content:gmatch("[^\r\n]+") do
        local key, value = line:match("^#|%s*([^:]+)%s*:%s*(.+)%s*$")
        if key and value then
            params[key:match("^%s*(.-)%s*$")] = value:match("^%s*(.-)%s*$")
        end
    end

    return params
end

--- This function gets the current code chunk based on the cursor position
---@param bufnr integer The buffer number.
---@return table
M.get_current_code_chunk = function(bufnr)
    local row, _ = unpack(vim.api.nvim_win_get_cursor(0))

    local chunks = get_code_chunks(bufnr)
    if not chunks then return {} end

    for _, chunk in ipairs(chunks) do
        local chunk_start_row, chunk_end_row = chunk:range()
        if row >= chunk_start_row and row <= chunk_end_row then return chunk end
    end

    return {}
end

-- Function to get all code chunks above the current cursor position
---@param bufnr integer The buffer number.
---@return table
M.get_chunks_above_cursor = function(bufnr)
    local row, _ = unpack(vim.api.nvim_win_get_cursor(0))

    local chunks = get_code_chunks(bufnr)

    if not chunks then return {} end

    local chunks_above = {}

    for _, chunk in ipairs(chunks) do
        local _, chunk_end_row = chunk:range()

        if chunk_end_row < row then table.insert(chunks_above, chunk) end
    end

    return chunks_above
end

--- This function gets all the code chunks in the buffer
---@param bufnr integer The buffer number.
---@return table|nil
M.get_all_code_chunks = function(bufnr)
    local chunks = get_code_chunks(bufnr)
    return chunks
end

--- This function filters the code chunks based on the language
---@param chunks table The code chunks.
---@param langs string[] The languages to filter by.
---@return table The filtered code chunks.
M.filter_code_chunks_by_lang = function(chunks, langs)
    local lang_set = {}
    for _, lang in ipairs(langs) do
        lang_set[lang] = true
    end

    return vim.tbl_filter(
        function(chunk) return type(chunk) == "table" and lang_set[chunk.lang] or false end,
        chunks
    )
end

--- This function filters the code chunks based on the eval parameter. If the eval parameter is not found it is assumed to be true
---@param chunks table
---@return table
M.filter_code_chunks_by_eval = function(chunks)
    -- If chunks is a single chunk (table), wrap it in a table to ensure uniform processing
    if type(chunks) ~= "table" or (type(chunks) == "table" and #chunks == 0) then
        chunks = { chunks }
    end

    return vim.tbl_filter(function(chunk)
        if type(chunk) ~= "table" then
            return false -- Skip this chunk if it’s not a table
        end

        -- Default eval is true if not provided
        local eval = true

        -- Check for eval in comment_params
        if chunk.comment_params and chunk.comment_params.eval then
            eval = chunk.comment_params.eval == "true"
        -- Check for eval in info_string_params
        elseif chunk.info_string_params and chunk.info_string_params.eval then
            eval = chunk.info_string_params.eval == "TRUE"
        end

        return eval -- Return true if eval is "true"
    end, chunks)
end

--- Formats the code chunks into a list of code lines that can be executed in
--- R. The code lines are formatted based on the language of the code chunk. If
--- the language is python, the code line is wrapped in
--- reticulate::py_run_string. If the language is R, the code line is returned
--- as is.
---@param chunks table The code chunks.
---@return table
M.codelines_from_chunks = function(chunks)
    local codelines = {}

    for _, chunk in ipairs(chunks) do
        local lang = chunk.lang
        local content = chunk.content

        if lang == "python" then
            table.insert(codelines, 'reticulate::py_run_string("' .. content .. '")')
        elseif lang == "r" then
            table.insert(codelines, content)
        end
    end

    return codelines
end

return M
