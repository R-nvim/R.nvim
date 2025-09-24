if
    vim.fn.exists("g:R_filetypes") == 1
    and type(vim.g.R_filetypes) == "table"
    and not vim.tbl_contains(vim.g.R_filetypes, "quarto")
then
    return
end

require("r.config").real_setup()
require("r.rmd").setup()

if not vim.lsp.config then return end

-- Check prerequisites before configuring yamlls
if vim.fn.executable("yaml-language-server") == 0 then return end

local schema_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
    .. "/lua/r/"
local document_schema = schema_dir .. "quarto-schema.json"
local project_schema = schema_dir .. "quarto-project-schema.json"

local yaml_settings = {
    yaml = {
        schemas = {
            ["file://" .. document_schema] = "*.qmd",
            ["file://" .. project_schema] = { "_quarto.yml", "_quarto.yaml" },
        },
        schemaStore = {
            enable = true,
            url = "https://www.schemastore.org/api/json/catalog.json",
        },
        validate = false,
        completion = true,
        hover = true,
    },
}

vim.lsp.config.yamlls = {
    cmd = { "yaml-language-server", "--stdio" },
    filetypes = { "quarto", "yaml" },
    root_markers = { ".git", "_quarto.yml", "_quarto.yaml" },
    settings = yaml_settings,
}

local function start_yamlls_with_schemas()
    vim.lsp.start({
        name = "yamlls",
        cmd = { "yaml-language-server", "--stdio" },
        root_dir = vim.fn.getcwd(),
        settings = yaml_settings,
    })
end

local function is_in_quarto_yaml()
    local filename = vim.fn.expand("%:t")

    -- Check if it's a _quarto.yml file
    if filename == "_quarto.yml" or filename == "_quarto.yaml" then return true end

    -- Check if it's frontmatter in a .qmd file
    local line_num = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(
        0,
        0,
        math.min(50, vim.api.nvim_buf_line_count(0)),
        false
    )

    -- Only consider YAML frontmatter at the beginning of the file
    local yaml_start, yaml_end = nil, nil

    if lines[1] and lines[1]:match("^---+%s*$") then
        yaml_start = 1
        -- Find the closing ---
        for i = 2, #lines do
            if lines[i]:match("^---+%s*$") then
                yaml_end = i
                break
            end
        end
    end

    local in_frontmatter = yaml_start
        and yaml_end
        and line_num > yaml_start
        and line_num < yaml_end

    return in_frontmatter
end

-- Manage yamlls attachment based on cursor position
vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = 0,
    callback = function()
        local in_yaml = is_in_quarto_yaml()

        local clients = vim.lsp.get_clients({ name = "yamlls", bufnr = 0 })
        local actually_attached = #clients > 0

        if in_yaml and not actually_attached then
            start_yamlls_with_schemas()
        elseif not in_yaml and actually_attached then
            for _, client in ipairs(clients) do
                vim.lsp.buf_detach_client(0, client.id)
            end
        end
    end,
})
