local warn = require("r").warn
local config = require("r.config").get_config()
local pdf = require("r.pdf")

local zathura_pid = {}

local has_dbus_send = vim.fn.executable("dbus-send") > 0 and 1 or 0

local ZathuraJobStdout = function(_, data, _)
    for _, cmd in ipairs(data) do
        if vim.startswith(cmd, "lua ") then vim.cmd(cmd) end
    end
end

local start2 = function(fullpath)
    local job_id = vim.fn.jobstart({
        "zathura",
        "--synctex-editor-command",
        'echo \'lua require("r.rnw").SyncTeX_backward("%{input}", "%{line}")\'',
        fullpath,
    }, {
        detach = true,
        -- FIXME:
        -- on_stderr = function(_, msg)
        --     ROnJobStderr(msg)
        -- end,
        on_stdout = function(_, data) ZathuraJobStdout(_, data, "stdout") end,
    })
    if job_id < 1 then
        warn("Failed to run Zathura...")
    else
        zathura_pid[fullpath] = vim.fn.jobpid(job_id)
    end
end

local start_zathura = function(fullpath)
    local fname = vim.fn.substitute(fullpath, ".*/", "", "")

    if zathura_pid[fullpath] and zathura_pid[fullpath] ~= 0 then
        -- Use the recorded pid to kill Zathura
        vim.fn.system("kill " .. zathura_pid[fullpath])
    elseif
        config.has_wmctrl
        and has_dbus_send
        and vim.fn.filereadable("/proc/sys/kernel/pid_max")
    then
        -- Use wmctrl to check if the pdf is already open and get Zathura's PID
        -- to close the document and kill Zathura.
        local info = vim.fn.filter(
            vim.fn.split(vim.fn.system("wmctrl -xpl"), "\n"),
            'v:val =~ "Zathura.*' .. fname .. '"'
        )
        if #info > 0 then
            local pid = vim.fn.split(info[1])[3] + 0 -- + 0 to convert into number
            local max_pid = tonumber(vim.fn.readfile("/proc/sys/kernel/pid_max")[1])
            if pid > 0 and pid <= max_pid then
                vim.fn.system(
                    "dbus-send --print-reply --session --dest=org.pwmt.zathura.PID-"
                        .. pid
                        .. " /org/pwmt/zathura org.pwmt.zathura.CloseDocument"
                )
                vim.wait(5)
                vim.fn.system("kill " .. pid)
                vim.wait(5)
            end
        end
    end

    start2(fullpath)
end

local M = {}

M.open = function(fullpath)
    if config.openpdf == 1 then
        start_zathura(fullpath)
        return
    end

    -- Time for Zathura to reload the PDF
    vim.wait(200)

    local fname = vim.fn.substitute(fullpath, ".*/", "", "")

    -- Check if Zathura was already opened and is still running
    if zathura_pid[fullpath] and zathura_pid[fullpath] ~= 0 then
        local zrun = vim.fn.system("ps -p " .. zathura_pid[fullpath])
        if zrun:find(zathura_pid[fullpath]) then
            if pdf.raise_window(fname) then
                return
            else
                start_zathura(fullpath)
                return
            end
        else
            zathura_pid[fullpath] = 0
            start_zathura(fullpath)
            return
        end
    else
        zathura_pid[fullpath] = 0
    end

    -- Check if Zathura was already running
    if fname == 0 then
        start_zathura(fullpath)
        return
    end
end

M.SyncTeX_forward = function(tpath, ppath, texln, tryagain)
    local texname = vim.fn.substitute(tpath, " ", "\\ ", "g")
    local pdfname = vim.fn.substitute(ppath, " ", "\\ ", "g")
    local shortp = vim.fn.substitute(ppath, ".*/", "", "g")

    if not zathura_pid[ppath] or (zathura_pid[ppath] and zathura_pid[ppath] == 0) then
        start_zathura(ppath)
        vim.wait(900)
    end

    local result = vim.fn.system(
        "zathura --synctex-forward="
            .. texln
            .. ":1:"
            .. texname
            .. " --synctex-pid="
            .. zathura_pid[ppath]
            .. " "
            .. pdfname
    )
    if vim.v.shell_error ~= 0 then
        zathura_pid[ppath] = 0
        if tryagain then
            start_zathura(ppath)
            vim.wait(900)
            M.SyncTeX_forward(tpath, ppath, texln, false)
        else
            warn(vim.fn.substitute(result, "\n", " ", "g"))
            return
        end
    end

    pdf.raise_window(shortp)
end

return M
