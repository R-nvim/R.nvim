local M = {}
local utils = require("r.lsp.utils")
local ast = require("r.lsp.ast")
local queries = require("r.lsp.queries")
local scope = require("r.lsp.scope")

-- kind: 3=Write if assignment target, else 2=Read
-- R grammar: all assignments are binary_operator with named fields lhs/rhs
-- Walk up to the nearest assignment ancestor so that compound targets like
-- x[1] <- 1, x$y <- 1, or names(x) <- ... are correctly classified as writes.
local assign_target =
    { ["<-"] = "lhs", ["<<-"] = "lhs", ["="] = "lhs", ["->"] = "rhs", ["->>"] = "rhs" }
local function highlight_kind(node, bufnr)
    local cur = node
    while true do
        local parent = cur:parent()
        if not parent then return 2 end
        if parent:type() == "binary_operator" then
            local op_node = parent:field("operator")[1]
            if op_node then
                local op = vim.treesitter.get_node_text(op_node, bufnr)
                local target_field = assign_target[op]
                if target_field then
                    local target = parent:field(target_field)[1]
                    return (target ~= nil and target == cur) and 3 or 2
                end
            end
        end
        cur = parent
    end
end

function M.document_highlight(req_id, line, col, bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local word, err = utils.get_word_at_bufpos(bufnr, line, col)
    if err or not word then
        utils.send_null(req_id)
        return
    end

    local current_scope = scope.get_scope_at_position(bufnr, line, col)
    local target_definition = current_scope and scope.resolve_symbol(word, current_scope)

    local query = queries.get("references")
    local _, root = ast.get_parser_and_root(bufnr)
    if not query or not root then
        utils.send_null(req_id)
        return
    end

    local highlights = {}
    for _, node in query:iter_captures(root, bufnr) do
        if
            not utils.is_argument_name_node(node)
            and vim.treesitter.get_node_text(node, bufnr) == word
        then
            local sr, sc = node:start()
            local _, ec = node:end_()

            local include = false
            if target_definition then
                local usage_scope = scope.get_scope_at_position(bufnr, sr, sc)
                if usage_scope then
                    local resolved = scope.resolve_symbol(word, usage_scope)
                    include = resolved ~= nil
                        and utils.is_same_r_variable(resolved, target_definition, bufnr)
                end
            else
                -- Symbol not resolved in scope: highlight all buffer occurrences
                include = true
            end

            if include then
                table.insert(highlights, {
                    range = {
                        start = { line = sr, character = sc },
                        ["end"] = { line = sr, character = ec },
                    },
                    kind = highlight_kind(node, bufnr),
                })
            end
        end
    end

    if #highlights > 0 then
        utils.send_response("L", req_id, { highlights = highlights })
    else
        utils.send_null(req_id)
    end
end

return M
