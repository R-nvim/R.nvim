local M = {}

local unquote_and_split_file_path = function(file_path)
    local quote = file_path:match("^[\"']")
    if quote then
        file_path = file_path:sub(2, -2) -- Remove surrounding quotes
    end

    -- Split the path into components
    local components = {}
    for component in file_path:gmatch("[^/]+") do
        table.insert(components, component)
    end

    -- If path starts with a /, add it to the first component
    if file_path:sub(1, 1) == "/" then components[1] = "/" .. components[1] end

    -- Join the components with the detected quote
    local result = table.concat(components, quote .. ", " .. quote)

    return result
end

local function replace_string(node, formatted_path)
    local bufnr = vim.api.nvim_get_current_buf()
    local start_row, start_col, end_row, end_col = node:range()

    vim.api.nvim_buf_set_text(
        bufnr,
        start_row,
        start_col,
        end_row,
        end_col,
        { formatted_path }
    )
end

M.split_path = function(prefix)
    local node = vim.treesitter.get_node()

    if node and node:type() == "string" then
        local path = vim.treesitter.get_node_text(node, 0)

        -- Check if the path is a URL or doesn't contain slashes
        if path:match("^(https?|ftp)://") or not path:match("/") then return end

        -- Traverse up the syntax tree until we find a call_expression node
        local parent = node:parent()
        while parent do
            if parent:type() == "call" then
                local function_name = vim.treesitter.get_node_text(parent, 0)
                if function_name:match("paste") or function_name:match("here") then
                    return
                end
            end
            parent = parent:parent()
        end

        -- Format the path
        local formatted_path = unquote_and_split_file_path(path)

        if prefix == "paste" then
            formatted_path = 'paste("' .. formatted_path .. '", sep = "/")'
        elseif prefix == "here" then
            formatted_path = 'here("' .. formatted_path .. '")'
        end

        replace_string(node, formatted_path)
    end
end

return M
