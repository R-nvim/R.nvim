--- This module provides functionality for managing jobs.
-- It includes mechanisms for starting jobs, processing their output, and managing their lifecycle.

local M = {}
local jobs = {}
local warn = require("r.log").warn

-- Structure to keep track of incomplete input data.
local incomplete_input = { size = 0, received = 0, str = "" }

--- Flag for whether we are waiting for more input to complete a command.
local waiting_more_input = false

-- Variables used for parsing command data.
local cmdsplt
local in_size
local received

--- Stops waiting for more input and logs a warning if an incomplete string was received.
local stop_waiting_nsr = function(_)
    if waiting_more_input then
        waiting_more_input = false
        warn(
            "Incomplete string received. Expected "
                .. incomplete_input.size
                .. " bytes; received "
                .. incomplete_input.received
                .. "."
        )
    end
    incomplete_input = { size = 0, received = 0, str = "" }
end

--- Begins waiting for more input to complete a command.
local begin_waiting_more_input = function ()
    waiting_more_input = true
    incomplete_input.size = in_size
    incomplete_input.received = received
    incomplete_input.str = cmdsplt[2]
    vim.fn.timer_start(1000, stop_waiting_nsr)
end

--- Executes a command received through stdout, if it matches known patterns.
---@param cmd string The command to execute.
---@param job_id number The ID of the job that produced the command.
local exec_stdout_cmd = function (cmd, job_id)
    if cmd:find("^lua ") then
        vim.fn.execute(cmd)
    else
        if cmd:len() > 128 then cmd = cmd:sub(1, 128) .. " [...]" end
        warn("[" .. M.get_title(job_id) .. "] Unknown command: " .. cmd)
    end
end

--- Handles stdout data from a job.
---@param job_id number The ID of the job.
---@param data table The data received from stdout.
M.on_stdout = function(job_id, data, _)
    local cmd
    for _, v in pairs(data) do
        cmd = v:gsub("\r", "")
        if #cmd > 0 then
            if cmd:sub(1, 1) == "\017" then
                cmdsplt = vim.fn.split(cmd, "\017")
                in_size = tonumber(cmdsplt[1])
                received = string.len(cmdsplt[2])
                if in_size == received then
                    cmd = cmdsplt[2]
                    exec_stdout_cmd(cmd, job_id)
                else
                    begin_waiting_more_input()
                end
            else
                if waiting_more_input then
                    incomplete_input.received = incomplete_input.received + cmd:len()
                    if incomplete_input.received == incomplete_input.size then
                        waiting_more_input = false
                        cmd = incomplete_input.str .. cmd
                        exec_stdout_cmd(cmd, job_id)
                    else
                        incomplete_input.str = incomplete_input.str .. cmd
                        if incomplete_input.received > incomplete_input.size then
                            warn("Received larger than expected message.")
                        end
                    end
                else
                    exec_stdout_cmd(cmd, job_id)
                end
            end
        end
    end
end

--- Handles stderr data from a job.
---@param job_id number The ID of the job.
---@param data table The data received from stderr.
M.on_stderr = function(job_id, data, _)
    local msg = table.concat(data):gsub("\r", "")
    if not msg:match("^%s*$") then warn("[" .. M.get_title(job_id) .. "] " .. msg) end
end

--- Handles the exit of a job.
---@param job_id number The ID of the job.
---@param data table The exit status of the job.
M.on_exit = function(job_id, data, _)
    local key = M.get_title(job_id)
    if key ~= "Job" then jobs[key] = 0 end
    if data ~= 0 then warn('"' .. key .. '"' .. " exited with status " .. data) end
    if key == "R" or key == "RStudio" then
        require("r.run").clear_R_info()
    end
    if key == "Server" then vim.g.R_Nvim_status = 1 end
end

local default_handlers = {
    on_stdout = M.on_stdout,
    on_stderr = M.on_stderr,
    on_exit = M.on_exit,
}

--- Starts a new job with the specified command and options.
---@param job_name string The name of the job.
---@param cmd table The command to start the job with.
---@param opt table|nil Optional table of handlers for job events.
M.start = function(job_name, cmd, opt)
    local h = default_handlers
    if opt then h = opt end
    local jobid = vim.fn.jobstart(cmd, h)
    if jobid == 0 then
        warn("Invalid arguments in: " .. tostring(cmd))
        return 0
    elseif jobid == -1 then
        warn("Command not executable in: " .. tostring(cmd))
        return 0
    end
    jobs[job_name] = jobid
end

--- Opens an R terminal with the specified command.
---@param cmd string The command to start the R terminal with.
M.R_term_open = function(cmd)
    local jobid = 0
    if vim.fn.has("nvim-0.12") == 1 then
        jobid = vim.fn.jobstart(cmd, { on_exit = M.on_exit, term = true })
    else
        jobid = vim.fn.termopen(cmd, { on_exit = M.on_exit })
    end
    if jobid == 0 then
        warn("Invalid arguments to run R in built-in terminal: " .. tostring(cmd))
    elseif jobid == -1 then
        warn("Command not executable: " .. tostring(cmd))
    else
        jobs["R"] = jobid
    end
end

--- Retrieves the title of a job by its ID.
---@param job_id number The ID of the job.
---@return string The title of the job or "Job" if not found.
M.get_title = function(job_id)
    for key, value in pairs(jobs) do
        if value == job_id then return key end
    end
    return "Job"
end

--- Get pid of job
---@param job_name string The job name.
---@return number
M.get_pid = function(job_name)
    if M.is_running(job_name) then
        return vim.fn.jobpid(jobs[job_name]) or 0
    end
    return 0
end

--- Sends a command to a job's stdin.
---@param job_name string The name of the job.
---@param cmd string The command to send.
M.stdin = function(job_name, cmd) vim.fn.chansend(jobs[job_name], cmd) end

--- Checks if a job is currently running.
---@param job_name string The name of the job.
---@return boolean True if the job is running, false otherwise.
M.is_running = function(job_name)
    if jobs[job_name] and jobs[job_name] ~= 0 then return true end
    return false
end

M.stop_rns = function()
    for k, v in pairs(jobs) do
        if M.is_running(k) and k == "Server" then
            -- Avoid warning of exit status 141
            vim.fn.chansend(v, "9\n")
            vim.wait(20)
        end
    end
end

-- Only called by R when finishing a session in a external terminal emulator.
-- We do know when the terminal exits, but when the terminal is closed Tmux is
-- only detached and R keeps running.
M.end_of_R_session = function ()
    jobs["R"] = 0
    require("r.run").clear_R_info()
end

return M
