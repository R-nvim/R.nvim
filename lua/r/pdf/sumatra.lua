local config = require("r.config").get_config()
local sumatra_in_path = false

---Check if Sumatra is in the PATH
---@return boolean
local function SumatraInPath()
    if sumatra_in_path then return true end

    if vim.env.PATH:find("SumatraPDF") then
        sumatra_in_path = true
        return true
    end

    -- $ProgramFiles has different values for win32 and win64
    local spaths = {
        os.getenv("LOCALAPPDATA") .. "\\SumatraPDF",
        os.getenv("ProgramFiles") .. "\\SumatraPDF",
    }
    for _, p in pairs(spaths) do
        if vim.fn.filereadable(p .. "\\SumatraPDF.exe") == 1 then
            vim.env.PATH = p .. ";" .. vim.env.PATH
            sumatra_in_path = true
            return true
        end
    end

    return false
end

local M = {}

---Open the PDF in SumatraPDF
---@param fullpath string
M.open = function(fullpath)
    if not SumatraInPath() then return end

    local pdir = vim.fs.dirname(fullpath)
    local olddir = vim.fs.normalize(vim.fn.getcwd()):gsub(" ", "\\ ")
    vim.cmd("cd " .. pdir)
    vim.fn.writefile({
        'start SumatraPDF.exe -reuse-instance -inverse-search "rnvimserver.exe %%f %%l" "'
            .. fullpath
            .. '"',
    }, vim.fs.joinpath(config.tmpdir, "run_cmd.bat"))
    vim.system({ vim.fs.joinpath(config.tmpdir, "run_cmd.bat") }, { detach = true })
    vim.cmd("cd " .. olddir)
    require("r.edit").add_for_deletion(vim.fs.joinpath(config.tmpdir, "run_cmd.bat"))
end

---Send the SyncTeX forward command to Sumatra
---@param tpath string
---@param ppath string
---@param texln number
M.SyncTeX_forward = function(tpath, ppath, texln)
    if not SumatraInPath() then return end

    -- Empty spaces must be removed from the rnoweb file name to get SyncTeX support with SumatraPDF.
    local tname = vim.fs.basename(tpath)
    local tdir = vim.fs.dirname(tpath)
    local pname = ppath:gsub(tdir .. "/", "")
    local olddir = vim.fs.normalize(vim.fn.getcwd()):gsub(" ", "\\ ")
    vim.cmd("cd " .. tdir:gsub(" ", "\\ "))
    vim.fn.writefile({
        'start SumatraPDF.exe -reuse-instance -forward-search "'
            .. tname
            .. '" '
            .. texln
            .. ' -inverse-search "rnvimserver.exe %%f %%l" "'
            .. pname
            .. '"',
    }, vim.fs.joinpath(config.tmpdir, "run_cmd.bat"))
    vim.system({ vim.fs.joinpath(config.tmpdir, "run_cmd.bat") }, { detach = true })
    vim.cmd("cd " .. olddir)
    require("r.edit").add_for_deletion(vim.fs.joinpath(config.tmpdir, "run_cmd.bat"))
end

return M
