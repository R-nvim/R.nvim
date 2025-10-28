local find_quarto_intel_unix = function(qpath2)
    if vim.fn.executable("quarto") ~= 1 then return nil end

    local handle = io.popen("which quarto")
    if handle then
        local quarto_bin = handle:read("*a")
        handle:close()
        local qpath1 = string.gsub(quarto_bin, "(.*)/.-/.*", "%1")
        local f = io.open(qpath1 .. qpath2, "r")
        if f then
            io.close(f)
            return qpath1 .. qpath2
        end

        handle = io.popen("readlink " .. quarto_bin)
        if handle then
            local quarto_dir2 = handle:read("*a")
            handle:close()
            quarto_dir2 = string.gsub(quarto_dir2, "(.*)/.-/.*", "%1")
            if string.find(quarto_dir2, "^%.%./") then
                while string.find(quarto_dir2, "^%.%./") do
                    quarto_dir2 = string.gsub(quarto_dir2, "^%.%./*", "")
                end
                quarto_dir2 = qpath1 .. "/" .. quarto_dir2
            end
            f = io.open(quarto_dir2 .. qpath2, "r")
            if f then
                io.close(f)
                return quarto_dir2 .. qpath2
            end
        end
    end
end

local find_quarto_intel_windows = function(qpath2)
    local path = os.getenv("PATH")
    if path then
        local paths = vim.fn.split(path, ";")
        vim.fn.filter(paths, 'v:val =~? "quarto"')
        if #paths > 0 then
            local qjson = string.gsub(paths[1], "bin$", qpath2)
            qjson = string.gsub(qjson, "\\", "/")
            local f = io.open(qjson, "r")
            if f then
                io.close(f)
                return qjson
            end
        end
    end
    return nil
end

local find_quarto_intel = function()
    local is_windows = vim.loop.os_uname().sysname:find("Windows") ~= nil
    local qpath2 = "/share/editor/tools/yaml/yaml-intelligence-resources.json"
    if is_windows then return find_quarto_intel_windows(qpath2) end
    return find_quarto_intel_unix(qpath2)
end

local M = {}

M.get_cell_opts = function(qmd_intel)
    local fname = vim.env.RNVIM_COMPLDIR .. "/quarto_block_items"

    -- FIXME: compare the modification dates of the yml and the fname
    if vim.fn.filereadable(fname) == 1 then return true end

    local qopts = {}
    local quarto_yaml_intel

    if qmd_intel then
        quarto_yaml_intel = qmd_intel
    else
        quarto_yaml_intel = find_quarto_intel()
    end

    if not quarto_yaml_intel then return false end

    local f = io.open(quarto_yaml_intel, "r")
    if not f then return false end
    local yaml_txt = f:read("*all")
    f:close()

    local intel = vim.fn.json_decode(yaml_txt)
    if not intel then return false end

    local cell_keys = {
        "schema/cell-attributes.yml",
        "schema/cell-cache.yml",
        "schema/cell-codeoutput.yml",
        "schema/cell-figure.yml",
        "schema/cell-include.yml",
        "schema/cell-layout.yml",
        "schema/cell-pagelayout.yml",
        "schema/cell-table.yml",
        "schema/cell-textoutput.yml",
    }
    for _, s in pairs(cell_keys) do
        if intel[s] then
            for _, item in pairs(intel[s]) do
                local lbl = item["name"] .. ": "
                local descr = nil
                if type(item["description"]) == "string" then
                    descr = item["description"]
                else
                    descr = item["description"]["long"]
                end
                descr = descr:gsub("\n", "\\n")
                table.insert(qopts, lbl .. "|" .. descr)
            end
        end
    end
    vim.fn.writefile(qopts, fname)
    return true
end

return M
