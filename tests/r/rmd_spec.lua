--# selene: allow(incorrect_standard_library_use)
--

local rmd = require("r.rmd")

-- local mock_cursor_position = require("tests.helpers").mock_cursor_position

describe("rmd module", function()
    -- before_each(function() mock.setup() end)
    -- after_each(function() mock.teardown() end)

    -- TODO: How does this function behave if chunk start/end not found?
    -- TODO: This function should work without defining a language
    -- TODO: Add test to check verbosity
    describe("is_in_code_chunk(language, verbose) Unit Tests", function()
        -- it("returns true if in R chunk", function()
        --   --TODO: Simulate cursor inside R chunk
        --   local rchunk_rmd = [[ ]] -- Moved to tests/examples/rmd/rchunk.rmd
        --   local handle = mock_cursor_position(rchunk_rmd, {15,3})
        --   assert.is_true(rmd.is_in_code_chunk("r", false)) -- FIX: call this from nvim not in standalone Lua
        --   handle:close()
        -- end)
        it("returns true if in R chunk", function()

        end)
        it("returns false if outside R chunk", function() return false end)
        it("returns true if in Python chunk", function() return false end)
        it("returns false if not in Python chunk", function() return false end)
        it("returns true if on an '```{r' line", function() return false end)
        it("returns true if on an '```' line that proceeds '```{r'", function() return false end)
    end)
end)

