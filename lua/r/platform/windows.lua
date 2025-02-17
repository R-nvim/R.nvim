local M = {}

local uv = vim.uv
local utils = require("r.utils")
local log = require("r.log")

function M.configure(config)
    local wtime = uv.hrtime()
    local isi386 = false

    if config.R_path ~= "" then
        local rpath = vim.split(config.R_path, ";")
        utils.resolve_fullpaths(rpath)
        vim.fn.reverse(rpath)
        for _, dir in ipairs(rpath) do
            if vim.fn.isdirectory(dir) then
                vim.env.PATH = dir .. ";" .. vim.env.PATH
            else
                log.warn(
                    '"'
                        .. dir
                        .. '" is not a directory. Fix the value of R_path in your config.'
                )
            end
        end
    else
        if vim.env.RTOOLS40_HOME then
            if vim.fn.isdirectory(vim.env.RTOOLS40_HOME .. "\\mingw64\\bin\\") then
                vim.env.PATH = vim.env.RTOOLS40_HOME .. "\\mingw64\\bin;" .. vim.env.PATH
            elseif vim.fn.isdirectory(vim.env.RTOOLS40_HOME .. "\\usr\\bin") then
                vim.env.PATH = vim.env.RTOOLS40_HOME .. "\\usr\\bin;" .. vim.env.PATH
            end
        else
            if vim.fn.isdirectory("C:\\rtools40\\mingw64\\bin") then
                vim.env.PATH = "C:\\rtools40\\mingw64\\bin;" .. vim.env.PATH
            elseif vim.fn.isdirectory("C:\\rtools40\\usr\\bin") then
                vim.env.PATH = "C:\\rtools40\\usr\\bin;" .. vim.env.PATH
            end
        end

        local get_rip = function(run_cmd)
            local resp = vim.system(run_cmd, { text = true }):wait()
            local rout = vim.split(resp.stdout, "\n")
            local rip = {}
            for _, v in pairs(rout) do
                if v:find("InstallPath.*REG_SZ") then table.insert(rip, v) end
            end
            return rip
        end

        -- Check both HKCU and HKLM. See #223
        local reg_roots = { "HKCU", "HKLM" }
        local rip = {}
        for i = 1, #reg_roots do
            if #rip == 0 then
                local run_cmd =
                    { "reg.exe", "QUERY", reg_roots[i] .. "\\SOFTWARE\\R-core\\R", "/s" }
                rip = get_rip(run_cmd)

                if #rip == 0 then
                    -- Normally, 32 bit applications access only 32 bit registry and...
                    -- We have to try again if the user has installed R only in the other architecture.
                    if vim.fn.has("win64") then
                        table.insert(run_cmd, "/reg:64")
                    else
                        table.insert(run_cmd, "/reg:32")
                    end
                    rip = get_rip(run_cmd)

                    if #rip == 0 and i == #reg_roots then
                        log.warn(
                            "Could not find R path in Windows Registry. "
                                .. "If you have already installed R, please, set the value of 'R_path'."
                        )
                        wtime = (uv.hrtime() - wtime) / 1000000000
                        require("r.edit").add_to_debug_info(
                            "windows setup",
                            wtime,
                            "Time"
                        )
                        return
                    end
                end
            end
        end

        local rinstallpath = nil
        rinstallpath = rip[1]
        rinstallpath = rinstallpath:gsub(".*InstallPath.*REG_SZ%s*", "")
        rinstallpath = rinstallpath:gsub("\n", "")
        rinstallpath = rinstallpath:gsub("%s*$", "")
        local hasR32 = vim.fn.isdirectory(rinstallpath .. "\\bin\\i386")
        local hasR64 = vim.fn.isdirectory(rinstallpath .. "\\bin\\x64")
        if hasR32 == 1 and hasR64 == 0 then isi386 = true end
        if hasR64 == 1 and hasR32 == 0 then isi386 = false end
        if hasR32 == 1 and isi386 then
            vim.env.PATH = rinstallpath .. "\\bin\\i386;" .. vim.env.PATH
        elseif hasR64 == 1 and not isi386 then
            vim.env.PATH = rinstallpath .. "\\bin\\x64;" .. vim.env.PATH
        else
            vim.env.PATH = rinstallpath .. "\\bin;" .. vim.env.PATH
        end
    end

    if not config.R_args then
        if config.external_term == "" then
            config.R_args = { "--no-save" }
        else
            config.R_args = { "--sdi", "--no-save" }
        end
    end
    wtime = (uv.hrtime() - wtime) / 1000000000
    require("r.edit").add_to_debug_info("windows setup", wtime, "Time")
end

return M
