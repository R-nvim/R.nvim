local config = require("r.config").get_config()
local sumatra_in_path = false
local warn = require("r.info").warn

---Check if Sumatra is in the PATH
---@return boolean
local function SumatraInPath()
    if sumatra_in_path then return true end

    if vim.env.PATH:find("SumatraPDF") then
        sumatra_in_path = true
        return true
    end

    -- $ProgramFiles has different values for win32 and win64
    if vim.fn.executable(os.getenv("ProgramFiles") .. "\\SumatraPDF\\SumatraPDF.exe") then
        vim.env.PATH = os.getenv("ProgramFiles") .. "\\SumatraPDF;" .. vim.env.PATH
        sumatra_in_path = true
        return true
    end

    if
        vim.fn.executable(
            os.getenv("ProgramFiles") .. " (x86)\\SumatraPDF\\SumatraPDF.exe"
        )
    then
        vim.env.PATH = os.getenv("ProgramFiles") .. " (x86)\\SumatraPDF;" .. vim.env.PATH
        sumatra_in_path = true
        return true
    end

    return false
end

local M = {}

---Open the PDF in SumatraPDF
---@param fullpath string
M.open = function(fullpath)
    if SumatraInPath() then
        local pdir = fullpath:gsub("(.*)/.*", "%1")
        local olddir = vim.fn.getcwd():gsub("\\", "/"):gsub(" ", "\\ ")
        vim.cmd("cd " .. pdir)
        vim.fn.writefile({
            'start SumatraPDF.exe -reuse-instance -inverse-search "rnvimserver.exe %%f %%l" "'
                .. fullpath
                .. '"',
        }, config.tmpdir .. "/run_cmd.bat")
        local obj = vim.system({ config.tmpdir .. "/run_cmd.bat" }, { text = true })
            :wait()
        if obj.code ~= 0 then warn("Error starting Sumatra: " .. obj.stderr) end
        vim.cmd("cd " .. olddir)
    end
end

---Send the SyncTeX forward command to Sumatra
---@param tpath string
---@param ppath string
---@param texln number
M.SyncTeX_forward = function(tpath, ppath, texln)
    -- Empty spaces must be removed from the rnoweb file name to get SyncTeX support with SumatraPDF.
    if SumatraInPath() then
        local tname = tpath:gsub(".*/(.*)", "%1")
        local tdir = tpath:gsub("(.*)/.*", "%1")
        local pname = ppath:gsub(tdir .. "/", "")
        local olddir = vim.fn.getcwd():gsub("\\", "/"):gsub(" ", "\\ ")
        vim.cmd("cd " .. tdir:gsub(" ", "\\ "))
        vim.fn.writefile({
            'start SumatraPDF.exe -reuse-instance -forward-search "'
                .. tname
                .. '" '
                .. texln
                .. ' -inverse-search "rnvimserver.exe %%f %%l" "'
                .. pname
                .. '"',
        }, config.tmpdir .. "/run_cmd.bat")
        local obj = vim.system({ config.tmpdir .. "/run_cmd.bat" }, { text = true })
            :wait()
        if obj.code ~= 0 then
            warn("Error running Sumatra forward search: " .. obj.stderr)
        end
        vim.cmd("cd " .. olddir)
    end
end

return M
