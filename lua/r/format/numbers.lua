local inform = require("r.log").inform
local create_r_buffer = require("r.buffer").create_r_buffer
local M = {}

--- Replace all implicit numbers in the current R buffer with explicit integers.
M.formatnum = function()
    local rbuf = create_r_buffer()

    if not rbuf then
        error("Failed to create R buffer")
        return
    end

    local r_content = table.concat(vim.api.nvim_buf_get_lines(rbuf, 0, -1, false), "\n")
    local r_parser = vim.treesitter.get_string_parser(r_content, "r")
    local r_tree = r_parser:parse()[1]
    local r_root = r_tree:root()

    local float_query = vim.treesitter.query.parse(
        "r",
        [[
        ((float) @value (#lua-match? @value "^%d+$"))
        ]]
    )

    -- Collect all floating point numbers in the R content from the "tmp" buffer
    local replacements = {}
    for _, node in float_query:iter_captures(r_root, r_content) do
        local start_row, start_col, end_row, end_col = node:range()
        local float_text = vim.treesitter.get_node_text(node, r_content)
        local new_text = float_text .. "L"

        table.insert(replacements, {
            start_row = start_row,
            start_col = start_col,
            end_row = end_row,
            end_col = end_col,
            text = new_text,
        })
    end

    -- Apply replacements in reverse order in the "main" buffer
    local current_bufnr = vim.api.nvim_get_current_buf()
    for i = #replacements, 1, -1 do
        local repl = replacements[i]
        vim.api.nvim_buf_set_text(
            current_bufnr,
            repl.start_row,
            repl.start_col,
            repl.end_row,
            repl.end_col,
            { repl.text }
        )
    end

    inform(#replacements .. " implicit numbers were replaced with integers.")
end

return M
