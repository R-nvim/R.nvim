-- ftplugin/yaml.lua - Handle _quarto.yml files
local filename = vim.fn.expand("%:t")

if filename == "_quarto.yml" or filename == "_quarto.yaml" then
    require("r.yaml").setup()
end
