if
    vim.g.R_filetypes
    and type(vim.g.R_filetypes) == "table"
    and not vim.tbl_contains(vim.g.R_filetypes, "typst")
then
    return
end

vim.treesitter.query.set(
    "typst",
    "injections",
    [[
; extends
(raw_blck
  (blob) @injection.content
  (#match? @injection.content "^\\{r\\}")
  (#offset! @injection.content 0 3 0 0)
  (#set! injection.language "r"))

(raw_blck
  (blob) @injection.content
  (#match? @injection.content "^\\{python\\}")
  (#offset! @injection.content 0 8 0 0)
  (#set! injection.language "python"))
]]
)

require("r.config").real_setup()
require("r.rmd").setup()
require("r.yaml").setup()
