local config = require("r.config").get_config()
local M = {}

-- We check if treesitter is available in the check_parsers() function of the
-- R.nvim plugin, so we can safely require the parsers module here.
local parsers = require("nvim-treesitter.parsers")

-- Define the Treesitter query
local query = [[
((float) @value (#lua-match? @value "^%d+$"))
]]

local function is_adjacent_char_colon(bufnr, start_row, start_col, end_row, end_col)
    -- Check if the previous or the next character is a colon in order to not add an "L" to the number. Should return only true or false
    local prev_char = vim.api.nvim_buf_get_text(
        bufnr,
        start_row,
        start_col - 1,
        start_row,
        start_col,
        {}
    )[1]

    local next_char =
        vim.api.nvim_buf_get_text(bufnr, end_row, end_col, end_row, end_col + 1, {})[1]

    return prev_char == ":" or next_char == ":"
end

M.formatnum = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local lang = parsers.get_buf_lang(bufnr)

    if not lang then return end

    local parser = parsers.get_parser(bufnr, lang)
    local tree = parser:parse()[1]
    local root = tree:root()

    local query_obj = vim.treesitter.query.parse(lang, query)
    -- local convert_range = config.convert_range_int

    for _, node in query_obj:iter_captures(root, bufnr, 0, -1) do
        local text = vim.treesitter.get_node_text(node, bufnr)

        local start_row, start_col, end_row, end_col = node:range()

        if
            not (
                is_adjacent_char_colon(bufnr, start_row, start_col, end_row, end_col)
                and config.convert_range_int == false
            )
        then
            vim.api.nvim_buf_set_text(
                bufnr,
                start_row,
                start_col,
                end_row,
                end_col,
                { text .. "L" }
            )
        end
    end
end

return M
