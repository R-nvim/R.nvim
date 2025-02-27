local config = require("r.config").get_config()

local M = {}

M.set_buf_options = function()
    if vim.o.filetype ~= "" then
        -- The buffer was previously used to display an R object.
        vim.api.nvim_set_option_value("filetype", "", { scope = "local" })
    end
    vim.api.nvim_set_option_value("number", false, { scope = "local" })
    vim.api.nvim_set_option_value("swapfile", false, { scope = "local" })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { scope = "local" })
    vim.api.nvim_set_option_value("buftype", "nofile", { scope = "local" })
    vim.api.nvim_set_option_value("iskeyword", "@,48-57,_,.", { scope = "local" })
    vim.api.nvim_set_option_value("signcolumn", "no", { scope = "local" })
    vim.api.nvim_set_option_value("foldcolumn", "0", { scope = "local" })
    vim.api.nvim_set_option_value("conceallevel", 2, { scope = "local" })
    if vim.bo.filetype ~= "rmd" then
        vim.api.nvim_set_option_value("filetype", "rmd", { scope = "local" })
    end

    vim.cmd([[
        syn match rdocArgReg / [A-Za-z\._]\{-} / contains=rdocArgDelim,rdocArgItem transparent
        syn match rdocArgItem /[A-Za-z\._]/ contained
        syn match rdocArgDelim / / contained conceal
        hi def link rdocArgItem Identifier
    ]])
    local buf = vim.api.nvim_get_current_buf()
    if vim.fn.has("nvim-0.11") == 1 then
        local ns = vim.api.nvim_create_namespace("RDocumentation")
        vim.hl.range(buf, ns, "Title", { 0, 1 }, { 0, -1 }, {})
    else
        vim.api.nvim_buf_add_highlight(buf, -1, "Title", 0, 0, -1)
    end
    require("r.config").real_setup()
    require("r.maps").create("rdoc")
end

---Prepare R documentation output to be displayed by Nvim
---@param txt string
---@return string[]
M.fix_rdoc = function(txt)
    txt = string.gsub(txt, "%_\008", "")
    txt = string.gsub(txt, "\019", "'")
    txt = string.gsub(txt, "\018", "\\")
    txt = string.gsub(txt, "<URL: %([^>]*%)>", " |%1|")
    txt = string.gsub(txt, "<email: %([^>]*%)>", " |%1|")
    if not config.is_windows then
        -- curly single quotes only if the environment is UTF-8
        txt = string.gsub(txt, "\145", "‘")
        txt = string.gsub(txt, "\146", "’")
    end

    -- Mark the end of Examples
    if txt:find("\020Examples:\020") then
        txt = txt:gsub("\020Examples:\020", "\020Examples:\020```{r}")
        txt = txt .. "```"
    end

    if txt:find("\020Usage:\020") then
        txt = txt:gsub("\020Usage:\020(.-)\020([A-Z])", "\020Usage:\020```{r}%1```\020%2")
    end

    local lines = vim.split(txt, "\020")
    local i = 1
    local j = #lines
    while i < j do
        if lines[i]:find("^[A-Z][a-z]+:") or lines[i]:find("^See Also:$") then
            -- Add a tab character before each section to mark its end.
            lines[i] = "# " .. lines[i]
            lines[i] = string.gsub(lines[i], ":$", "")
            -- Add an empty space to make the highlighting of the first argument work
            if lines[i] == "# Arguments" then
                i = i + 1
                while i < j and not lines[i]:find("^[A-Z]") do
                    lines[i] = lines[i]:gsub("^ *", "")
                    if lines[i]:find("^[A-Za-z%._, ]*: ") and lines[i - 1] == "" then
                        lines[i] = lines[i]:gsub(
                            "^([A-Za-z%._, ]*): ",
                            function(x)
                                return string.gsub(x, "([A-Za-z%._]+)(,*)", " %1 %2")
                                    .. ": "
                            end
                        )
                    end
                    lines[i] = lines[i]:gsub("‘", "`")
                    lines[i] = lines[i]:gsub("’", "`")
                    i = i + 1
                end
                i = i - 1
            end
        end
        lines[i] = lines[i]:gsub("^     ", "")
        lines[i] = lines[i]:gsub("‘", "`")
        lines[i] = lines[i]:gsub("’", "`")
        i = i + 1
    end
    return lines
end

return M
