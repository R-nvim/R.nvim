local M = {}

--- Get fig and tbl labels
---@param input string
---@return table
M.get_labels = function(input)
    local chunks = require("r.quarto").get_code_chunks(0)
    if not chunks then return {} end
    local resp = {}
    for _, c in pairs(chunks) do
        if
            c.comment_params.label
            and (
                c.comment_params.label:find("^fig") or c.comment_params.label:find("^tbl")
            )
        then
            local lbl = "@" .. c.comment_params.label
            local cap = nil
            if lbl:find("^" .. input) then
                local item = {
                    label = lbl,
                    kind = vim.lsp.protocol.CompletionItemKind.Reference,
                }
                if c.comment_params["fig-cap"] then
                    cap = c.comment_params["fig-cap"]
                elseif c.comment_params["tbl-cap"] then
                    cap = c.comment_params["tbl-cap"]
                end
                if cap then
                    item.documentation = {
                        kind = vim.lsp.protocol.MarkupKind.Markdown,
                        value = cap,
                    }
                end
                table.insert(resp, item)
            end
        end
    end
    return resp
end

return M
