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

--- Find and replace floating point numbers in the given R content.
---@param bufnr  integer The buffer number.
---@param lang string The language of the code chunk.
---@param row integer|nil The row number. If nil, all code chunks are returned.
---@return table|nil
M.get_code_chunk = function(bufnr, lang, row)
    local root = require("r.utils").get_root_node()

    if not root then return nil end

    local query = vim.treesitter.query.parse(
        "markdown",
        string.format(
            [[
                (fenced_code_block
                (info_string (language) @lang (#eq? @lang "%s"))
                (code_fence_content) @content)
            ]],
            lang
        )
    )

    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local r_contents = {}
    for _, node, _ in query:iter_captures(root, bufnr, 0, -1) do
        if node:type() == "code_fence_content" then
            local start_row, _, end_row, _ = node:range()
            if not row or (row >= start_row and row <= end_row) then
                table.insert(r_contents, {
                    content = vim.treesitter.get_node_text(node, bufnr),
                    start_row = start_row,
                    end_row = end_row,
                })
                if row then break end
            end
        end
    end
    return r_contents
end

return M
