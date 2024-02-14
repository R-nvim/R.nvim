local config = require("r.config").get_config()
local sumatra_in_path = 0

local function SumatraInPath()
    if sumatra_in_path ~= 0 then return 1 end

    if vim.env.PATH:find("SumatraPDF") then
        sumatra_in_path = 1
        return 1
    end

    -- $ProgramFiles has different values for win32 and win64
    if vim.fn.executable(os.getenv("ProgramFiles") .. "\\SumatraPDF\\SumatraPDF.exe") then
        vim.env.PATH = os.getenv("ProgramFiles") .. "\\SumatraPDF;" .. vim.env.PATH
        sumatra_in_path = 1
        return 1
    end

    if
        vim.fn.executable(
            os.getenv("ProgramFiles") .. " (x86)\\SumatraPDF\\SumatraPDF.exe"
        )
    then
        vim.env.PATH = os.getenv("ProgramFiles") .. " (x86)\\SumatraPDF;" .. vim.env.PATH
        sumatra_in_path = 1
        return 1
    end

    return 0
end

local M = {}

M.open = function(fullpath)
    if SumatraInPath() then
        local pdir = vim.fn.substitute(fullpath, "\\(.*\\)/.*", "\\1", "")
        local olddir = vim.fn.substitute(
            vim.fn.substitute(vim.fn.getcwd(), "\\", "/", "g"),
            " ",
            "\\ ",
            "g"
        )
        vim.cmd("cd " .. pdir)
        vim.fn.writefile({
            'start SumatraPDF.exe -reuse-instance -inverse-search "rnvimserver.exe %%f %%l" "'
                .. fullpath
                .. '"',
        }, config.tmpdir .. "/run_cmd.bat")
        vim.fn.system(config.tmpdir .. "/run_cmd.bat")
        vim.cmd("cd " .. olddir)
    end
end

M.SyncTeX_forward = function(tpath, ppath, texln)
    -- Empty spaces must be removed from the rnoweb file name to get SyncTeX support with SumatraPDF.
    if SumatraInPath() then
        local tname = vim.fn.substitute(tpath, ".*/\\(.*\\)", "\\1", "")
        local tdir = vim.fn.substitute(tpath, "\\(.*\\)/.*", "\\1", "")
        local pname = vim.fn.substitute(ppath, tdir .. "/", "", "")
        local olddir = vim.fn.substitute(
            vim.fn.substitute(vim.fn.getcwd(), "\\", "/", "g"),
            " ",
            "\\ ",
            "g"
        )
        vim.cmd("cd " .. vim.fn.substitute(tdir, " ", "\\ ", "g"))
        vim.fn.writefile({
            'start SumatraPDF.exe -reuse-instance -forward-search "'
                .. tname
                .. '" '
                .. texln
                .. ' -inverse-search "rnvimserver.exe %%f %%l" "'
                .. pname
                .. '"',
        }, config.tmpdir .. "/run_cmd.bat")
        vim.fn.system(config.tmpdir .. "/run_cmd.bat")
        vim.cmd("cd " .. olddir)
    end
end

return M
