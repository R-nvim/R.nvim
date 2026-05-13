if
    vim.g.R_filetypes
    and type(vim.g.R_filetypes) == "table"
    and not vim.tbl_contains(vim.g.R_filetypes, "typst")
then
    return
end

pcall(
    vim.treesitter.query.set,
    "typst",
    "injections",
    [[
; extends
(raw_blck
  (blob) @injection.content
  (#match? @injection.content "^\\{r[,}\\s]")
  (#offset! @injection.content 1 0 0 0)
  (#set! injection.language "r"))

(raw_blck
  (blob) @injection.content
  (#match? @injection.content "^\\{python[,}\\s]")
  (#offset! @injection.content 1 0 0 0)
  (#set! injection.language "python"))
]]
)

require("r.config").real_setup()
require("r.rmd").setup()
require("r.yaml").setup()
