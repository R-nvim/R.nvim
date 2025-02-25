local M = {}

local config = require("r.config").get_config()
local warn = require("r.log").warn
local r_width = 80
local number_col
local r_bufnr = nil

---Send command to R running a built-in terminal emulator
---@param command string
---@return boolean
M.send_cmd = function(command)
    local is_running
    require("r.job").is_running("R")
    if is_running == 0 then
        warn("Is R running?")
        return false
    end

    if config.is_windows then require("r.run").send_to_nvimcom("B", "R is Busy") end

    local cmd
    if config.clear_line then
        if config.editing_mode == "emacs" then
            cmd = "\001\011" .. command
        else
            cmd = "\0270Da" .. command
        end
    else
        cmd = command
    end

    -- Update the width, if necessary
    local bwid = vim.fn.bufwinid(r_bufnr)
    if config.setwidth ~= 0 and config.setwidth ~= 2 and bwid ~= -1 then
        local rwnwdth = vim.fn.winwidth(bwid)
        if rwnwdth ~= r_width and rwnwdth ~= -1 and rwnwdth > 10 and rwnwdth < 999 then
            r_width = rwnwdth
            local width = r_width + number_col
            if config.is_windows then
                cmd = "options(width=" .. width .. "); " .. cmd
            else
                require("r.run").send_to_nvimcom("E", "options(width=" .. width .. ")")
                vim.wait(10)
            end
        end
    end

    -- if config.auto_scroll and not string.find(cmd, '^quit(') and bwid ~= -1 then
    if config.auto_scroll and bwid ~= -1 then
        vim.api.nvim_win_set_cursor(
            bwid,
            { vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(bwid)), 0 }
        )
    end

    if type(cmd) == "table" then
        cmd = table.concat(cmd, "\n") .. "\n"
    else
        cmd = cmd .. "\n"
    end
    require("r.job").stdin("R", cmd)
    return true
end

M.close_term = function()
    if not r_bufnr then return end
    if not vim.api.nvim_buf_is_valid(r_bufnr) then
        r_bufnr = nil
        return
    end
    vim.cmd.sb(r_bufnr)
    if config.close_term then
        vim.cmd("startinsert")
        vim.fn.feedkeys(" ")
    end
    r_bufnr = nil
end

local split_window = function()
    local n
    if vim.o.number then
        n = 1
    else
        n = 0
    end
    if
        config.rconsole_width > 0
        and vim.fn.winwidth(0)
            > (config.rconsole_width + config.min_editor_width + 1 + (n * vim.o.numberwidth))
    then
        if
            config.rconsole_width > 16
            and config.rconsole_width < (vim.fn.winwidth(0) - 17)
        then
            vim.cmd("silent exe 'belowright " .. config.rconsole_width .. "vnew'")
        else
            vim.cmd("silent belowright vnew")
        end
    else
        if
            config.rconsole_height > 0
            and config.rconsole_height < (vim.fn.winheight(0) - 1)
        then
            vim.cmd("silent exe 'belowright " .. config.rconsole_height .. "new'")
        else
            vim.cmd("silent belowright new")
        end
    end
end

M.reopen_win = function()
    if not r_bufnr then return end
    local wlist = vim.api.nvim_list_wins()
    for _, wnr in ipairs(wlist) do
        if vim.api.nvim_win_get_buf(wnr) == r_bufnr then
            -- The R buffer is visible
            return
        end
    end
    local edbuf = vim.api.nvim_get_current_buf()
    split_window()
    vim.api.nvim_win_set_buf(0, r_bufnr)
    vim.cmd.sb(edbuf)
end

M.start = function()
    vim.g.R_Nvim_status = 6

    local edbuf = vim.api.nvim_get_current_buf()
    vim.o.switchbuf = "useopen"

    split_window()

    if config.is_windows then require("r.windows").set_R_home() end
    require("r.job").R_term_open(config.R_app .. " " .. require("r.run").get_r_args())
    if config.is_windows then
        -- vim.cmd("redraw") -- superfluous?
        require("r.windows").unset_R_home()
    end
    r_bufnr = vim.api.nvim_get_current_buf()
    if config.esc_term then
        vim.api.nvim_buf_set_keymap(
            0,
            "t",
            "<Esc>",
            "<C-\\><C-n>",
            { noremap = true, silent = true }
        )
    end
    for _, optn in ipairs(vim.fn.split(config.buffer_opts, "\n")) do
        vim.cmd("setlocal " .. optn)
    end

    if
        vim.api.nvim_get_option_value("number", { win = vim.api.nvim_get_current_win() })
    then
        if config.setwidth < 0 and config.setwidth > -17 then
            number_col = config.setwidth
        else
            number_col = -6
        end
    else
        number_col = 0
    end

    vim.cmd.sb(edbuf)
    vim.cmd("stopinsert")
    require("r.run").wait_nvimcom_start()
end

M.highlight_term = function()
    if r_bufnr then vim.api.nvim_set_option_value("syntax", "rout", { buf = r_bufnr }) end
end

---Return built-in terminal buffer number
---@return number | nil
M.get_buf_nr = function() return r_bufnr end

return M
