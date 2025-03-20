local assert = require("luassert")
local test_utils = require("./utils")

describe(
    "In quarto document, get_lang() function correctly identifies languages",
    function()
        local bufnr

        before_each(function()
            bufnr = test_utils.create_r_buffer_from_file("tests/fixtures/langs.qmd")
            vim.api.nvim_set_current_buf(bufnr)
        end)

        local function test_lang(cursor_pos, expected_lang, description)
            it(description, function()
                vim.api.nvim_win_set_cursor(0, cursor_pos)
                local detected_lang = require("r.utils").get_lang()
                assert.same(
                    expected_lang,
                    detected_lang,
                    "Expected language not detected"
                )
            end)
        end

        local test_cases = {
            { { 1, 0 }, "markdown", "detect markdown code" },
            { { 5, 0 }, "markdown", "detect markdown code" },
            { { 7, 0 }, "r", "detect r code" },
            { { 8, 0 }, "r", "detect r code" },
            { { 14, 0 }, "python", "detect python code" },
            { { 15, 0 }, "python", "detect python code" },
            -- { { 2, 1 }, "yaml", "detect yaml code" },
            -- { { 12, 1 }, "markdown_inline", "detect markdown_inline code" },
        }

        for _, case in ipairs(test_cases) do
            test_lang(case[1], case[2], case[3])
        end
    end
)
