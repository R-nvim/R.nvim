--# selene: allow(incorrect_standard_library_use)
---@diagnostic disable: undefined-global
local utils = require("r.utils")

--- See tests/init/lua
local function root(root_folder)
    local f = debug.getinfo(1, "S").source:sub(2)
    return vim.fn.fnamemodify(f, ":p:h:h") .. "/" .. (root_folder or "")
end

describe("normalize_windows_path", function()
    it("converts backslashes to forward slashes", function()
        local path = "C:\\Users\\Example\\Documents"
        local expected = "C:/Users/Example/Documents"
        assert.are.equal(expected, utils.normalize_windows_path(path))
    end)
end)

-- TODO: Add tests for Windows
-- TODO: Add tests for Mac
describe("ensure_directory_exists", function()
    local test_cache_directory = root(".tests/cache")

    it("should return true because the directory already exists (Unix)", function()
        local existing_directory = test_cache_directory -- Created by init.lua
        assert.is_true(utils.ensure_directory_exists(existing_directory))
    end)

    it(
        "should create the directory and return true if it does not exist (Unix)",
        function()
            local new_directory = test_cache_directory .. "/new-unix-directory"
            assert.is_true(utils.ensure_directory_exists(new_directory))
            os.execute("rm -r " .. new_directory) -- Clean up: Remove the created directory
        end
    )

    it(
        "should return false if an error occurs during directory creation (Unix)",
        function()
            local protectedDir = "/create_me" -- Attempt to create a directory in a protected Unix directory
            assert.is_false(utils.ensure_directory_exists(protectedDir))
        end
    )
end)
