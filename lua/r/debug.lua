------------------------------------------------------------------------------
-- Support for debugging R code
------------------------------------------------------------------------------
local config = require("r.config").get_config()

local r_bufnr
local M = {}

-- Handle ambiwidth option and define signs
if vim.o.ambiwidth == "double" then
    vim.fn.sign_define(
        "dbgline",
        { text = "==>", texthl = "SignColumn", linehl = "QuickFixLine" }
    )
else
    vim.fn.sign_define(
        "dbgline",
        { text = "▬▶", texthl = "SignColumn", linehl = "QuickFixLine" }
    )
end

local s = {
    func_offset = -2, -- Did not seek yet
    rdebugging = 0
}

local find_func = function(srcref)
    local rlines
    -- local can_debug = type(config.external_term) == "boolean" and not config.external_term
    -- if not can_debug then return end

    s.func_offset = -1 -- Not found
    local sbopt = vim.o.switchbuf
    vim.o.switchbuf = "useopen,usetab"
    local curtab = vim.fn.tabpagenr()
    local isnormal = vim.fn.mode() == "n"
    local curwin = vim.fn.winnr()
    r_bufnr = vim.api.nvim_get_current_buf()
    vim.cmd("sb " .. r_bufnr)
    -- vim.fn.sleep(30) -- Time to fill the buffer lines
    rlines = vim.fn.getline(1, "$")
    vim.cmd("sb " .. vim.fn.bufname(require("r.edit").get_rscript_buf()))

    local idx = #rlines - 1
    while idx > 0 do
        if string.match(rlines[idx], "^debugging in: ") then
            local funcnm = string.gsub(rlines[idx], "^debugging in: %(.{-}%)%((.*)", "%1")
            s.func_offset =
                vim.fn.search(".*\\<" .. funcnm .. "\\s*<-\\s*function\\s*(", "b")
            if s.func_offset < 1 then
                s.func_offset =
                    vim.fn.search(".*\\<" .. funcnm .. "\\s*=\\s*function\\s*(", "b")
            end
            if s.func_offset < 1 then
                s.func_offset =
                    vim.fn.search(".*\\<" .. funcnm .. "\\s*<<-\\s*function\\s*(", "b")
            end
            if s.func_offset > 0 then s.func_offset = s.func_offset - 1 end
            if srcref == "<text>" then
                if vim.bo.filetype == "rmd" or vim.bo.filetype == "quarto" then
                    s.func_offset = vim.fn.search("^\\s*```\\s*{\\s*r", "nb")
                elseif vim.bo.filetype == "rnoweb" then
                    s.func_offset = vim.fn.search("^<<", "nb")
                end
            end
            break
        end
        idx = idx - 1
    end

    curtab = vim.fn.tabpagenr()
    if vim.fn.tabpagenr() ~= curtab then vim.cmd("normal! " .. curtab .. "gt") end
    curwin = vim.fn.winnr()
    vim.cmd(curwin .. "wincmd w")
    isnormal = vim.fn.mode() == "n"
    if isnormal then vim.cmd("stopinsert") end

    vim.o.switchbuf = sbopt
end

M.stop = function()
    vim.fn.sign_unplace("rnvim_dbgline", { id = 1 })
    s.func_offset = -2
    s.rdebugging = 0
end

--- Jump to line being evaluated
---@param fnm string The file name
---@param lnum number The line number
M.jump = function(fnm, lnum)
    local saved_so = vim.o.scrolloff
    if config.debug_center then vim.o.scrolloff = 999 end

    if fnm == "" or fnm == "<text>" then
        --- Functions sent directly to R Console have no associated source file
        --- and functions sourced by knitr have '<text>' as source reference.
        if s.func_offset == -2 then find_func(fnm) end
        if s.func_offset < 0 then return end
    end

    local flnum, fname
    if s.func_offset >= 0 then
        flnum = lnum + s.func_offset
        fname = vim.fn.bufname(require("r.edit").get_rscript_buf())
    else
        flnum = lnum
        fname = vim.fn.expand(fnm)
    end

    if
        vim.fn.bufloaded(fname) == 0
        and fname ~= vim.fn.bufname(require("r.edit").get_rscript_buf())
        and fname ~= vim.fn.expand("%")
        and fname ~= vim.fn.expand("%:p")
    then
        if vim.fn.filereadable(fname) == 1 or vim.fn.glob("*") == fname then
            vim.cmd("sb " .. vim.fn.bufname(require("r.edit").get_rscript_buf()))
            if vim.bo.modified then vim.cmd("split") end
            vim.cmd("edit " .. fname)
        else
            return
        end
    end

    if vim.fn.bufloaded(fname) == 1 then
        if fname ~= vim.fn.expand("%") then vim.cmd("sb " .. fname) end
        vim.cmd(":" .. flnum)
    end

    local bname = vim.fn.bufname("%")

    r_bufnr = vim.api.nvim_get_current_buf()
    vim.fn.sign_unplace("rnvim_dbgline", { id = 1 })
    vim.fn.sign_place(1, "rnvim_dbgline", "dbgline", r_bufnr, { lnum = flnum })
    if
        config.debug_jump
        and not s.rdebugging
        and type(config.external_term) == "boolean"
        and not config.external_term
    then
        vim.cmd("sb " .. r_bufnr)
        vim.cmd("startinsert")
    elseif bname ~= vim.fn.expand("%") then
        vim.cmd("sb " .. bname)
    end
    s.rdebugging = 1
    vim.o.scrolloff = saved_so
end

return M
