local M = {}
local jobs = {}
local warn = require("r").warn

local incomplete_input = { size = 0, received = 0, str = "" }
local waiting_more_input = false
local cmdsplt
local in_size
local received

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

local begin_waiting_more_input = function ()
    -- Log("begin_waiting_more_input")
    waiting_more_input = true
    incomplete_input.size = in_size
    incomplete_input.received = received
    incomplete_input.str = cmdsplt[2]
    vim.fn.timer_start(100, stop_waiting_nsr)
end

local exec_stdout_cmd = function (cmd, job_id)
    if cmd:match("^(lua |call |let)")then
        vim.fn.execute(cmd)
    else
        if cmd:len() > 128 then cmd = cmd:sub(1, 128) .. " [...]" end
        warn("[" .. M.get_title(job_id) .. "] Unknown command: " .. cmd)
    end
end

M.on_stdout = function(job_id, data, _)
    local cmd
    for _, v in pairs(data) do
        cmd = v:gsub("\r", "")
        if #cmd > 0 then
            if cmd:sub(1, 1) == "\017" then
                cmdsplt = vim.fn.split(cmd, "\017")
                in_size = vim.fn.str2nr(cmdsplt[1])
                received = vim.fn.strlen(cmdsplt[2])
                if in_size == received then
                    cmd = cmdsplt[2]
                    -- Log("split but complete: " .. cmd:len())
                    exec_stdout_cmd(cmd, job_id)
                else
                    begin_waiting_more_input()
                end
            else
                if waiting_more_input then
                    incomplete_input.received = incomplete_input.received + cmd:len()
                    if incomplete_input.received == incomplete_input.size then
                        -- Log("input completed")
                        waiting_more_input = true
                        cmd = incomplete_input.str .. cmd
                        exec_stdout_cmd(cmd, job_id)
                    else
                        incomplete_input.str = incomplete_input.str .. cmd
                        if incomplete_input.received > incomplete_input.size then
                            warn("Received larger than expected message.")
                        end
                    end
                else
                    -- Log("no need to wait: " .. cmd:len())
                    exec_stdout_cmd(cmd, job_id)
                end
            end
        end
    end
end

M.on_stderr = function(job_id, data, _)
    local msg = table.concat(data):gsub("\r", "")
    if not msg:match("^%s*$") then warn("[" .. M.get_title(job_id) .. "] " .. msg) end
end

M.on_exit = function(job_id, data, _)
    local key = M.get_title(job_id)
    if key ~= "Job" then jobs[key] = 0 end
    if data ~= 0 then warn('"' .. key .. '"' .. " exited with status " .. data) end
    if key == "R" or key == "RStudio" then
        if M.is_running("Server") then
            vim.g.R_Nvim_status = 3
        else
            vim.g.R_Nvim_status = 1
        end
        require("r.run").clear_R_info()
    end
    if key == "Server" then vim.g.R_Nvim_status = 1 end
end

local default_handlers = {
    on_stdout = M.on_stdout,
    on_stderr = M.on_stderr,
    on_exit = M.on_exit,
}

M.start = function(nm, cmd, opt)
    local h = default_handlers
    if opt then h = opt end
    local jobid = vim.fn.jobstart(cmd, h)
    if jobid == 0 then
        warn("Invalid arguments in: " .. tostring(cmd))
    elseif jobid == -1 then
        warn("Command not executable in: " .. tostring(cmd))
    else
        jobs[nm] = jobid
    end
end

M.R_term_open = function(cmd)
    local jobid = vim.fn.termopen(cmd, { on_exit = M.on_exit })
    if jobid == 0 then
        warn("Invalid arguments R in built-in terminal: " .. tostring(cmd))
    elseif jobid == -1 then
        warn("Command not executable: " .. tostring(cmd))
    else
        jobs["R"] = jobid
    end
end

M.get_title = function(job_id)
    for key, value in pairs(jobs) do
        if value == job_id then return key end
    end
    return "Job"
end

M.stdin = function(job, cmd) vim.fn.chansend(jobs[job], cmd) end

M.is_running = function(key)
    if jobs[key] and jobs[key] ~= 0 then return true end
    return false
end

M.stop_nrs = function()
    for k, v in pairs(jobs) do
        if M.is_running(k) and k == "Server" then
            -- Avoid warning of exit status 141
            vim.fn.chansend(v, "9\n")
            vim.wait(20)
        end
    end
end

return M
