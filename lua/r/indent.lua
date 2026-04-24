local M = {}

local PIPE_OPS = { ["|>"] = true, ["%>%"] = true, ["+"] = true }

local function is_pipe_op(bufnr, op_nodes)
    if not op_nodes or not op_nodes[1] then return false end
    return PIPE_OPS[vim.treesitter.get_node_text(op_nodes[1], bufnr)] == true
end

---@param bufnr integer
---@param row integer 1-indexed line number of the previous (pipe) line
---@return integer?
local function pipe_continuation_indent(bufnr, row)
    local _, root = require("r.lsp.ast").get_parser_and_root(bufnr)
    if not root then return nil end

    local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
    local search_col = math.max(0, #line:gsub("%s+$", "") - 1)

    local node = root:descendant_for_range(row - 1, search_col, row - 1, search_col)
    if not node then return nil end

    local pipe_root = nil
    local current = node
    while current do
        if current:type() == "binary_operator" then
            if is_pipe_op(bufnr, current:field("operator")) then
                pipe_root = current
            elseif pipe_root then
                break
            end
        elseif pipe_root then
            break
        else
            -- treesitter error-recovery: trailing |> becomes a direct child of an
            -- ERROR node rather than a binary_operator RHS, so scan siblings before it.
            local node_id = node:id()
            local last_named_sibling = nil
            for child in current:iter_children() do
                if child:id() == node_id then break end
                if
                    child:type() == "binary_operator"
                    and is_pipe_op(bufnr, child:field("operator"))
                then
                    pipe_root = child
                end
                if child:named() then last_named_sibling = child end
            end
            if pipe_root then break end
            -- First step of chain: anchor on the identifier/call before |>.
            if last_named_sibling then
                local _, col = last_named_sibling:start()
                return col + vim.fn.shiftwidth()
            end
        end
        current = current:parent()
    end

    if pipe_root then
        local _, col = pipe_root:start()
        return col + vim.fn.shiftwidth()
    end
    return nil
end

---@param lnum integer 1-indexed target line
---@return integer indent in columns, or -1 to fall back to autoindent
function M.get_indent(lnum)
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

    if line:match("^%s*$") then
        local prev_lnum = vim.fn.prevnonblank(lnum - 1)
        if prev_lnum > 0 then
            local prev_line = vim.api.nvim_buf_get_lines(
                bufnr,
                prev_lnum - 1,
                prev_lnum,
                false
            )[1] or ""
            if
                prev_line:match("|>%s*$")
                or prev_line:match("%%>%%%s*$")
                or prev_line:match("%+%s*$")
            then
                local indent = pipe_continuation_indent(bufnr, prev_lnum)
                if indent then return indent end
            end
        end
    end

    -- fall back to nvim-treesitter (try both old and new API)
    local ok, ts = pcall(require, "nvim-treesitter")
    if ok and ts.indentexpr then
        vim.v.lnum = lnum
        return vim.fn.eval("v:lua.require'nvim-treesitter'.indentexpr()")
    end
    local ok2, ts_indent = pcall(require, "nvim-treesitter.indent")
    if ok2 then return ts_indent.get_indent(lnum) end
    return -1
end

return M

