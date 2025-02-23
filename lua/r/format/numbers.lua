local inform = require("r.log").inform
local get_code_chunk = require("r.quarto").get_code_chunk

local M = {}

--- Find and replace floating point numbers in the given R content.
-- @param r_content The R content as a string.
-- @param bufnr The buffer number.
-- @param chunk_start_row The starting row of the chunk.
-- @param chunk_start_col The starting column of the chunk.
local function find_and_replace_float(r_content, bufnr, chunk_start_row, chunk_start_col)
    local r_parser = vim.treesitter.get_string_parser(r_content, "r")
    local r_tree = r_parser:parse()[1]
    local r_root = r_tree:root()

    local float_query = vim.treesitter.query.parse(
        "r",
        [[
        ((float) @value (#lua-match? @value "^%d+$"))
        ]]
    )

    local replacements = {}
    for _, node in float_query:iter_captures(r_root, r_content) do
        local start_row, start_col, end_row, end_col = node:range()
        local float_text = vim.treesitter.get_node_text(node, r_content)
        local new_text = float_text .. "L"

        table.insert(replacements, {
            start_row = chunk_start_row + start_row,
            start_col = chunk_start_col + start_col,
            end_row = chunk_start_row + end_row,
            end_col = chunk_start_col + end_col,
            text = new_text,
        })
    end

    -- Apply replacements in reverse order
    for i = #replacements, 1, -1 do
        local repl = replacements[i]
        vim.api.nvim_buf_set_text(
            bufnr,
            repl.start_row,
            repl.start_col,
            repl.end_row,
            repl.end_col,
            { repl.text }
        )
    end
end

--- Format numbers in the current buffer.
-- This function formats numbers in R, Quarto, and RMarkdown files.
-- It replaces floating point numbers with integers followed by 'L'.
-- @param bufnr The buffer number (optional).
M.formatnum = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local filetype = vim.bo[bufnr].filetype

    if filetype ~= "r" and filetype ~= "quarto" and filetype ~= "rmd" then
        inform("Not yet supported in '" .. filetype .. "' files.")
        return
    end

    if filetype == "quarto" or filetype == "rmd" then
        local r_chunks_content = get_code_chunk(bufnr, "r")

        if not r_chunks_content then
            error("Failed to extract code chunks.")
            return
        end

        for _, r_chunk in ipairs(r_chunks_content) do
            find_and_replace_float(r_chunk.content, bufnr, r_chunk.start_row, 0)
        end
    else
        local buffer_content =
            table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")

        find_and_replace_float(buffer_content, bufnr, 0, 0)
    end
end

return M
