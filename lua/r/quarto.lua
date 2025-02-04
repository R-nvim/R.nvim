local M = {}

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

-- Helper function to get R content/code block from Quarto document
-- @param root The root node of the parsed tree
-- @param bufnr The buffer number
-- @param cursor_pos The cursor position (optional)
-- @return A table containing R code blocks with their content, start row and end row
M.get_r_chunks_from_quarto = function(root, bufnr, cursor_pos)
    local query = vim.treesitter.query.parse(
        "markdown",
        [[
        (fenced_code_block
          (info_string (language) @lang (#eq? @lang "r"))
          (code_fence_content) @content)
        ]]
    )

    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local r_contents = {}
    for _, node, _ in query:iter_captures(root, bufnr, 0, -1) do
        if node:type() == "code_fence_content" then
            local start_row, _, end_row, _ = node:range()
            if not cursor_pos or (cursor_pos >= start_row and cursor_pos <= end_row) then
                table.insert(r_contents, {
                    content = vim.treesitter.get_node_text(node, bufnr),
                    start_row = start_row,
                    end_row = end_row,
                })
                if cursor_pos then break end
            end
        end
    end
    return r_contents
end

return M
