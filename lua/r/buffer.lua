local inform = require("r.log").inform
local warn = require("r.log").warn

local M = {}

local get_root_node = require("r.utils").get_root_node

--- Creates an R buffer from the current buffer or a specified buffer number.
--- If the current buffer is already an R file, it returns the current buffer number.
--- For Quarto, or RMarkdown files, it extracts R code chunks and creates a new buffer.
--- @return integer|nil The buffer number of the created R buffer, or nil if creation fails.
M.create_r_buffer = function()
    local bufnr = vim.api.nvim_get_current_buf()

    local filetype = vim.bo[bufnr].filetype

    if filetype == "r" then return bufnr end

    if not vim.tbl_contains({ "markdown", "rmd", "quarto" }, filetype) then
        inform("Not yet supported in '" .. filetype .. "' files.")
        return
    end

    local query = vim.treesitter.query.parse(
        "markdown",
        [[
         (fenced_code_block
           (info_string (language) @lang)
           (code_fence_content) @content)
         ]]
    )

    local is_r = require("r.chunk").is_r
    local lines = {}
    local last_end = 0

    local root = get_root_node(bufnr)
    if not root then return end

    for _, match in query:iter_matches(root, bufnr, 0, -1, { all = true }) do
        local lang_node, content_node
        for id, nodes in pairs(match) do
            local name = query.captures[id]
            if name == "lang" then lang_node = nodes[#nodes] end
            if name == "content" then content_node = nodes[#nodes] end
        end

        local lang = lang_node and vim.treesitter.get_node_text(lang_node, bufnr)
        if content_node and lang and is_r(lang) then
            local start_row, _, end_row, _ = content_node:range()

            -- Replace non-R content (including the chunk delimiters) with
            -- blank lines
            for _ = last_end, start_row - 1 do
                table.insert(lines, "")
            end

            vim.list_extend(
                lines,
                vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, false)
            )

            last_end = end_row
        end
    end

    -- Replace remaining non-R content at the end with blank lines
    local buffer_line_count = vim.api.nvim_buf_line_count(bufnr)
    for _ = last_end, buffer_line_count - 1 do
        table.insert(lines, "")
    end

    local rbuf = vim.api.nvim_create_buf(false, true)

    if not rbuf then
        warn("Failed to create R buffer.")
        return
    end

    vim.api.nvim_buf_set_lines(rbuf, 0, -1, false, lines)
    vim.bo[rbuf].filetype = "r"

    return rbuf
end

return M
