-- ftplugin/yaml.lua - Handle _quarto.yml files
local filename = vim.fn.expand("%:t")

if filename == "_quarto.yml" or filename == "_quarto.yaml" then
    -- Load the quarto configuration
    dofile(
        vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
            .. "/quarto_rnvim.lua"
    )
end
