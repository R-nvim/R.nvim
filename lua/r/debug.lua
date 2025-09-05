------------------------------------------------------------------------------
-- Support for debugging R code
------------------------------------------------------------------------------
local config = require("r.config").get_config()
local warn = require("r.log").warn

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
    debugging = false,
    bufnr = -1,
    winnr = -1,
    func_offset = -2, -- Did not seek yet
    fnm = "",
}

local switch_buf = function(fnm)
    if vim.api.nvim_get_current_buf() ~= require("r.edit").get_rscript_buf() then
        vim.cmd("sb " .. tostring(require("r.edit").get_rscript_buf()))
    end
    if vim.bo.modified then vim.cmd("split") end
    vim.cmd("edit " .. fnm)
    s.bufnr = vim.api.nvim_get_current_buf()
    s.winnr = vim.api.nvim_get_current_win()
end

local get_bultin_rlines = function()
    local rbn = require("r.term.builtin").get_buf_nr()
    if not rbn then
        warn("Failed to get R buffer number.")
        return nil
    end
    local rlines = vim.api.nvim_buf_get_lines(rbn, 0, -1, false)
    return rlines
end

local get_cmd_output = function(run_cmd)
    local obj = vim.system(run_cmd, { text = true }):wait()
    if obj.code ~= 0 then
        warn("Error running `" .. table.concat(run_cmd, " ") .. "`:\n" .. obj.stderr)
        return nil
    end
    local rlines = vim.split(obj.stdout, "\n")
    return rlines
end

local get_wezterm_rlines = function()
    local run_cmd = {
        "wezterm",
        "cli",
        "get-text",
        "--pane-id",
        require("r.term.wezterm").get_r_pane(),
    }
    return get_cmd_output(run_cmd)
end

local get_kitty_rlines = function()
    local kaddr = require("r.term.kitty").get_kaddr()
    local run_cmd = {
        "kitten",
        "@",
        "get-text",
        "--to",
        kaddr,
        "-m",
        "id:1",
    }
    return get_cmd_output(run_cmd)
end

local get_kitty_split_rlines = function()
    local run_cmd = {
        "kitten",
        "@",
        "get-text",
        "-m",
        "id:" .. require("r.term.kitten").get_r_wid(),
    }
    return get_cmd_output(run_cmd)
end

local get_tmux_rlines = function()
    local run_cmd = {
        "tmux",
        "-L",
        "Rnvim",
        "capture-pane",
        "-p",
        "-t",
        require("r.term.tmux").get_tmuxsname(),
    }
    return get_cmd_output(run_cmd)
end

local get_rlines = function()
    if config.external_term == "" then
        return get_bultin_rlines()
    elseif
        config.external_term == "wezterm" or config.external_term == "wezterm_split"
    then
        return get_wezterm_rlines()
    elseif config.external_term == "kitty" then
        return get_kitty_rlines()
    elseif config.external_term == "kitty_split" then
        return get_kitty_split_rlines()
    else
        return get_tmux_rlines()
    end
end

local find_func = function(srcref)
    s.func_offset = -1 -- Not found

    local rlines = get_rlines()
    if not rlines then return end
    vim.wait(300)

    local idx = #rlines - 1
    while idx > 0 do
        if
            string.find(rlines[idx], "^debugging in: ")
            or string.find(rlines[idx], "^Called from: ")
        then
            -- Get the function name
            local func_name = string.gsub(rlines[idx], "debugging in: ", "")
            func_name = func_name:gsub("Called from: ", "")
            func_name = string.gsub(func_name, "%(.*", "")

            -- Seek the function in the current buffer
            s.func_offset =
                vim.fn.search(".*\\<" .. func_name .. "\\s*<-\\s*function\\s*(", "b")
            if s.func_offset < 1 then
                s.func_offset =
                    vim.fn.search(".*\\<" .. func_name .. "\\s*=\\s*function\\s*(", "b")
            end
            if s.func_offset < 1 then
                s.func_offset =
                    vim.fn.search(".*\\<" .. func_name .. "\\s*<<-\\s*function\\s*(", "b")
            end
            if s.func_offset > 0 then
                s.bufnr = vim.api.nvim_get_current_buf()
                s.winnr = vim.api.nvim_get_current_win()
                s.func_offset = s.func_offset - 1
                if srcref == "<text>" then
                    if
                        vim.tbl_contains({ "markdown", "rmd", "quarto" }, vim.bo.filetype)
                    then
                        s.func_offset = vim.fn.search("^\\s*```\\s*{\\s*r", "nb")
                    elseif vim.bo.filetype == "rnoweb" then
                        s.func_offset = vim.fn.search("^<<", "nb")
                    end
                end
            else
                -- Function not found in the current buffer. Get it from RConsole.
                idx = idx + 1
                if string.find(rlines[idx], "%{$") then
                    local func_lines = {}
                    table.insert(func_lines, func_name .. " <- function() " .. "{")
                    idx = idx + 1
                    while rlines[idx] ~= "}" and idx < #rlines do
                        table.insert(func_lines, rlines[idx])
                        idx = idx + 1
                    end
                    table.insert(func_lines, "}")
                    if vim.fn.filereadable("__" .. func_name .. ".R") then
                        switch_buf("__" .. func_name .. ".R")
                        vim.api.nvim_set_option_value(
                            "swapfile",
                            false,
                            { scope = "local" }
                        )
                        vim.api.nvim_set_option_value(
                            "bufhidden",
                            "wipe",
                            { scope = "local" }
                        )
                        vim.api.nvim_set_option_value(
                            "buftype",
                            "nofile",
                            { scope = "local" }
                        )
                        vim.api.nvim_buf_set_lines(0, 0, -1, true, func_lines)
                    end
                end
            end
            break
        end
        idx = idx - 1
    end
end

M.stop = function()
    vim.fn.sign_unplace("rnvim_dbgline", { id = 1 })
    s = {
        debugging = false,
        bufnr = -1,
        func_offset = -2, -- Did not seek yet
        fnm = "",
    }
end

--- Jump to line being evaluated
---@param fnm string The file name
---@param lnum number The line number
M.jump = function(fnm, lnum)
    -- Open function's script is if not open yet
    if not s.debugging or s.fnm ~= fnm then
        s.fnm = fnm
        if fnm == "" or fnm == "<text>" then
            --- Functions sent directly to R Console have no associated source file
            --- and functions sourced by knitr have '<text>' as source reference.
            if s.func_offset == -2 then find_func(fnm) end
            if s.func_offset < 0 then return end
        else
            local fname = vim.fn.expand(fnm)
            if vim.fn.bufloaded(fname) == 0 then
                if vim.fn.filereadable(fname) == 1 or vim.fn.glob("*") == fname then
                    switch_buf(fname)
                else
                    return
                end
            else
                switch_buf(fname)
            end
        end
    end

    -- Move the cursor and highlight its line
    if vim.fn.bufloaded(s.bufnr) == 1 then
        local flnum
        if s.func_offset >= 0 then
            flnum = lnum + s.func_offset
        else
            flnum = lnum
        end

        local saved_so = vim.o.scrolloff
        if config.debug_center then vim.o.scrolloff = 999 end
        vim.api.nvim_win_set_cursor(s.winnr, { flnum, 0 })
        if config.debug_center then vim.o.scrolloff = saved_so end

        vim.fn.sign_unplace("rnvim_dbgline", { id = 1 })
        vim.fn.sign_place(1, "rnvim_dbgline", "dbgline", s.bufnr, { lnum = flnum })
    end

    if
        config.debug_jump
        and config.external_term == ""
        and vim.api.nvim_get_current_buf() ~= require("r.term.builtin").get_buf_nr()
    then
        vim.cmd("sb " .. tostring(require("r.term.builtin").get_buf_nr()))
        vim.cmd("startinsert")
    end

    s.debugging = true
end

return M
