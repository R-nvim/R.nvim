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

--- Helper function to get code block from Rmd or Quarto document
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

--- Helper function to get code block info from Rmd or Quarto document
---@return table|nil
M.get_ts_chunks = function()
    local root = require("r.utils").get_root_node()

    if not root then return nil end

    local query = vim.treesitter.query.parse(
        "markdown",
        [[
           (fenced_code_block) @fcb
        ]]
    )

    local bufnr = vim.api.nvim_get_current_buf()
    local chunks = {}
    for _, node, _ in query:iter_captures(root, 0, bufnr, -1) do
        local lang = "unknown"
        for cn in node:iter_children() do
            if cn:type() == "info_string" then
                for ic in cn:iter_children() do
                    if ic:type() == "language" then
                        lang = vim.treesitter.get_node_text(ic, bufnr)
                    end
                end
            end
        end
        local start_row, _, end_row, _ = node:range()
        table.insert(chunks, {
            lang = lang,
            start_row = start_row + 1,
            end_row = end_row + 1,
        })
    end
    return chunks
end

return M
