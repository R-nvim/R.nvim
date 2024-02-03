local config = require("r.config").get_config()
local warn = require("r").warn

-- Check if the cursor is in the Examples section of R documentation
local is_in_R_code = function (vrb)
    local exline = vim.fn.search("^Examples:$", "bncW")
    if exline > 0 and vim.fn.line(".") > exline then
        return 1
    else
        if vrb then
            warn('Not in the "Examples" section.')
        end
        return 0
    end
end

local M = {}

M.set_buf_options = function ()
    vim.api.nvim_buf_set_var(0, "IsInRCode", is_in_R_code)
    vim.api.nvim_set_option_value("number",            false, { scope = "local" })
    vim.api.nvim_set_option_value("swapfile",          false, { scope = "local" })
    vim.api.nvim_set_option_value("syntax",           "rdoc", { scope = "local" })
    vim.api.nvim_set_option_value("bufhidden",        "wipe", { scope = "local" })
    vim.api.nvim_set_option_value("buftype",        "nofile", { scope = "local" })
    vim.api.nvim_set_option_value("iskeyword", "@,48-57,_,.", { scope = "local" })

    require("r.maps").create("rdoc")
end

-- Prepare R documentation output to be displayed by Nvim
M.fix_rdoc = function ()
    local lnr = vim.fn.line('$')
    for ii = 1, lnr do
        local lii = vim.fn.getline(ii)
        lii = string.gsub(lii, "_\010", "")
        lii = string.gsub(lii, '<URL: %([^>]*%)>', ' |%1|')
        lii = string.gsub(lii, '<email: %([^>]*%)>', ' |%1|')
        if not config.is_windows then
            -- curly single quotes only if the environment is UTF-8
            lii = string.gsub(lii, "\x91", "‘")
            lii = string.gsub(lii, "\x92", "’")
        end
        vim.fn.setline(ii, lii)
    end

    -- Mark the end of Examples
    local ii = vim.fn.search("^Examples:$", "nw")
    if ii ~= 0 then
        if vim.fn.getline(vim.fn.line('$')) ~= "^###$" then
            lnr = vim.fn.line('$') + 1
            vim.fn.setline(lnr, '###')
        end
    end

    -- Add a tab character at the end of the Arguments section to mark its end.
    ii = vim.fn.search("^Arguments:$", "nw")
    if ii ~= 0 then
        -- A space after 'Arguments:' is necessary for correct syntax highlight
        -- of the first argument
        vim.fn.setline(ii, "Arguments: ")
        local doclength = vim.fn.line('$')
        ii = ii + 2
        local lin = vim.fn.getline(ii)
        while not lin:match("^[A-Z].*:") and ii < doclength do
            ii = ii + 1
            lin = vim.fn.getline(ii)
        end
        if ii < doclength then
            ii = ii - 1
            if vim.fn.getline(ii) == "^$" then
                vim.fn.setline(ii, " \t")
            end
        end
    end

    -- Add a tab character at the end of the Usage section to mark its end.
    ii = vim.fn.search("^Usage:$", "nw")
    if ii ~= 0 then
        local doclength = vim.fn.line('$')
        ii = ii + 2
        local lin = vim.fn.getline(ii)
        while not lin:match("^[A-Z].*:") and ii < doclength do
            ii = ii + 1
            lin = vim.fn.getline(ii)
        end
        if ii < doclength then
            ii = ii - 1
            if vim.fn.getline(ii) == "^ *$" then
                vim.fn.setline(ii, "\t")
            end
        end
    end

    vim.cmd('normal! gg')

    -- Clear undo history
    local old_undolevels = vim.o.undolevels
    vim.o.undolevels = -1
    vim.cmd([[normal! a \<BS>\<Esc>]])
    vim.o.undolevels = old_undolevels
end

-- Move the cursor to the Examples section in R documentation
M.go_to_ex_section = function ()
    local ii = vim.fn.search("^Examples:$", "nW")
    if ii == 0 then
        warn("No example section below.")
    else
        vim.fn.cursor(ii + 1, 1)
    end
end

return M
