if
    vim.g.R_filetypes
    and type(vim.g.R_filetypes) == "table"
    and not vim.tbl_contains(vim.g.R_filetypes, "typst")
then
    return
end

--- Build typst injection queries dynamically from chunk_langs config.
--- Generates one entry per canonical language and its aliases.
local function build_typst_injections()
    local config = require("r.config").get_config()
    local langs = config.chunk_langs
    if not langs then return "" end

    local parts = { "; extends" }

    for lang, lang_cfg in pairs(langs) do
        local names = { lang }
        if lang_cfg.aliases then
            for _, alias in ipairs(lang_cfg.aliases) do
                table.insert(names, alias)
            end
        end

        for _, name in ipairs(names) do
            local escaped = name:gsub("([^%w])", "\\%1")
            -- Build match pattern: ^\\{name[,\\}\\s]
            local match_pat = "^"
                .. "\\\\"
                .. "{"
                .. escaped
                .. "[,"
                .. "\\\\"
                .. "}"
                .. "\\\\"
                .. "s]"

            local entry = "(raw_blck\n"
                .. "  (blob) @injection.content\n"
                .. '  (#match? @injection.content "'
                .. match_pat
                .. '")\n'
                .. "  (#offset! @injection.content 1 -3 0 0)\n"
                .. '  (#set! injection.language "'
                .. lang
                .. '"))'

            table.insert(parts, entry)
        end
    end

    return table.concat(parts, "\n\n")
end

if vim.api.nvim_buf_get_name(0):lower():find("%.rtyp$") then
    pcall(vim.treesitter.query.set, "typst", "injections", build_typst_injections())
end

require("r.config").real_setup()
require("r.rmd").setup()
require("r.yaml").setup()
