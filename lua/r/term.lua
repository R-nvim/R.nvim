M = {}

local config = require("r.config").get_config()
local warn = require("r").warn
local R_width = 80
local number_col
local R_bufnr = nil
local is_windows = vim.loop.os_uname().sysname:find("Windows") ~= nil

M.send_cmd_to_term = function(command, nl)
	local is_running
	require("r.job").is_running("R")
	if is_running == 0 then
		warn("Is R running?")
		return 0
	end

	local cmd
	if config.clear_line then
		if config.editing_mode == "emacs" then
			cmd = "\001\013" .. command
		else
			cmd = "\x1b0Da" .. command
		end
	else
		cmd = command
	end

	-- Update the width, if necessary
	local bwid = vim.fn.bufwinid(R_bufnr)
	if config.setwidth ~= 0 and config.setwidth ~= 2 and bwid ~= -1 then
		local rwnwdth = vim.fn.winwidth(bwid)
		if rwnwdth ~= R_width and rwnwdth ~= -1 and rwnwdth > 10 and rwnwdth < 999 then
			R_width = rwnwdth
			local Rwidth = R_width + number_col
			if config.is_windows then
				cmd = "options(width=" .. Rwidth .. "); " .. cmd
			else
				require("r.run").send_to_nvimcom("E", "options(width=" .. Rwidth .. ")")
				vim.wait(10)
			end
		end
	end

	-- if config.auto_scroll and not string.find(cmd, '^quit(') and bwid ~= -1 then
	if config.auto_scroll and bwid ~= -1 then
		vim.api.nvim_win_set_cursor(bwid, { vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(bwid)), 0 })
	end

	if nl ~= false then
		if type(cmd) == "table" then
			cmd = table.concat(cmd, "\n") .. "\n"
		else
			cmd = cmd .. "\n"
		end
	end
	require("r.job").stdin("R", cmd)
	return 1
end

M.close_term = function()
	if R_bufnr then
		vim.cmd.sb(R_bufnr)
		if config.close_term and R_bufnr == vim.fn.bufnr("%") then
			vim.cmd("startinsert")
			vim.fn.feedkeys(" ")
		end
		R_bufnr = nil
	end
	R_bufnr = nil
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
		and vim.fn.winwidth(0) > (config.rconsole_width + config.min_editor_width + 1 + (n * vim.o.numberwidth))
	then
		if config.rconsole_width > 16 and config.rconsole_width < (vim.fn.winwidth(0) - 17) then
			vim.cmd("silent exe 'belowright " .. config.rconsole_width .. "vnew'")
		else
			vim.cmd("silent belowright vnew")
		end
	else
		if config.rconsole_height > 0 and config.rconsole_height < (vim.fn.winheight(0) - 1) then
			vim.cmd("silent exe 'belowright " .. config.rconsole_height .. "new'")
		else
			vim.cmd("silent belowright new")
		end
	end
end

local reopen_win = function()
	local wlist = vim.api.nvim_list_wins()
	for _, wnr in ipairs(wlist) do
		if vim.api.nvim_win_get_buf(wnr) == R_bufnr then
			-- The R buffer is visible
			return
		end
	end
	local edbuf = vim.fn.bufname("%")
	split_window()
	vim.api.nvim_win_set_buf(0, R_bufnr)
	vim.cmd.sb(edbuf)
end

M.start_term = function()
	-- Check if R is running
	if vim.g.R_Nvim_status == 5 then
		reopen_win()
		return
	end
	vim.g.R_Nvim_status = 4

	local edbuf = vim.fn.bufname("%")
	vim.o.switchbuf = "useopen"

	split_window()

	if config.is_windows then require("r.windows").set_R_home() end
	require("r.job").R_term_open(config.R_app .. " " .. table.concat(config.R_args, " "))
	if config.is_windows then
		vim.cmd("redraw")
		require("r.windows").unset_R_home()
	end
	R_bufnr = vim.fn.bufnr("%")
	if config.hl_term then vim.cmd("silent set syntax=rout") end
	if config.esc_term then
		vim.api.nvim_buf_set_keymap(0, "t", "<Esc>", "<C-\\><C-n>", { noremap = true, silent = true })
	end
	for _, optn in ipairs(vim.fn.split(config.buffer_opts, "\n")) do
		vim.cmd("setlocal " .. optn)
	end

	if vim.b.number then
		if config.setwidth < 0 and config.setwidth > -17 then
			number_col = config.setwidth
		else
			number_col = -6
		end
	else
		number_col = 0
	end

	-- Set b:pdf_is_open to avoid an error when the user has to go to R Console
	-- to deal with latex errors while compiling the pdf
	vim.b.pdf_is_open = 1
	vim.cmd.sb(edbuf)
	vim.cmd("stopinsert")
	require("r.run").wait_nvimcom_start()
end

M.highlight_term = function()
	if R_bufnr then vim.api.nvim_set_option_value("syntax", "rout", { buf = R_bufnr }) end
end

M.clear_console = function()
	if config.clear_console == false then return end

	if vim.fn.has("win32") and type(config.external_term) == "boolean" and config.external_term then
	-- TODO
	else
		-- TODO
	end
end

M.clear_all = function()
	if config.rmhidden then
		M.send_cmd_to_term("rm(list=ls(all.names = TRUE))", true)
	else
		M.send_cmd_to_term("rm(list = ls())", true)
	end

	M.clear_console()
end

M.get_buf_nr = function() return R_bufnr end

return M
