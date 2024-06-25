local M = {}

local parsers = require("nvim-treesitter.parsers")

-- Define the Treesitter query for capturing nodes
local query = [[
(dollar
    (identifier)
    (dollar
        (identifier)
        (dollar
            (identifier)
        )*
    )*
) @expression
]]

-- Function to traverse nodes and build the replacement string
local function build_replacement(node, bufnr)
    local identifiers = {}

    -- Function to recursively collect identifier text
    local function collect_identifiers(inner_node)
        if inner_node:type() == "identifier" then
            local text = vim.treesitter.get_node_text(inner_node, bufnr)
            if text ~= "" then table.insert(identifiers, text) end
        else
            local child_count = inner_node:named_child_count()
            for i = 0, child_count - 1 do
                local child_node = inner_node:named_child(i)
                collect_identifiers(child_node)
            end
        end
    end

    -- Start collecting identifiers from the node
    collect_identifiers(node)

    -- Construct the replacement string
    local replacement = table.remove(identifiers, 1)
    for _, id in ipairs(identifiers) do
        replacement = replacement .. string.format('[["%s"]]', id)
    end
    return replacement
end

M.formatsubsetting = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local lang = parsers.get_buf_lang(bufnr)

    if not lang then return end

    local parser = parsers.get_parser(bufnr, lang)
    local tree = parser:parse()[1]
    local root = tree:root()

    -- Parse the query
    local query_obj = vim.treesitter.query.parse(lang, query)

    for _, node, _ in query_obj:iter_captures(root, bufnr, 0, -1) do
        local replacement = build_replacement(node, bufnr)
        local range = { node:range() }
        vim.api.nvim_buf_set_text(
            bufnr,
            range[1],
            range[2],
            range[3],
            range[4],
            { replacement }
        )
    end
end

return M
