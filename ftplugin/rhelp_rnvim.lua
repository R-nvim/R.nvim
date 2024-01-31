if vim.fn.exists("g:R_filetypes") == 1 and type(vim.g.R_filetypes) == "table" and vim.fn.index(vim.g.R_filetypes, 'rhelp') == -1 then
    return
end

-- Override default values with user variable options and set internal variables.
require("r.config").real_setup()

local is_in_R_code = function(vrb)
    local lastsec = vim.fn.search("^\\\\[a-z][a-z]*{", "bncW")
    local secname = vim.fn.getline(lastsec)
    if vim.fn.line(".") > lastsec and (secname == '\\usage{' or
        secname == '\\examples{' or secname == '\\dontshow{' or
        secname == '\\dontrun{' or secname == '\\donttest{' or
        secname == '\\testonly{') then
        return 1
    else
        if vrb then
            require("r").warn("Not inside an R section.")
        end
        return 0
    end
end

vim.b.IsInRCode = is_in_R_code

-- Key bindings and menu items
require("r.maps").start()
require("r.maps").edit()
require("r.maps").send()
require("r.maps").control()
require("r.maps").create('nvi', 'RSetwd', 'rd', ':call RSetWD()')

if vim.b.undo_ftplugin then
    vim.b.undo_ftplugin = vim.b.undo_ftplugin .. " | unlet! b:IsInRCode"
else
    vim.b.undo_ftplugin = "unlet! b:IsInRCode"
end
