local M = {}

M.is_in_R_code = function(vrb)
    local lastsec = vim.fn.search("^\\\\[a-z][a-z]*{", "bncW")
    local secname = vim.fn.getline(lastsec)
    if
        vim.fn.line(".") > lastsec
        and (
            secname == "\\usage{"
            or secname == "\\examples{"
            or secname == "\\dontshow{"
            or secname == "\\dontrun{"
            or secname == "\\donttest{"
            or secname == "\\testonly{"
        )
    then
        return 1
    else
        if vrb then require("r").warn("Not inside an R section.") end
        return 0
    end
end

return M
