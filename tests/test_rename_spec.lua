local assert = require("luassert")
local stub = require("luassert.stub")
local test_utils = require("./utils")

describe("LSP textDocument/rename", function()
    local rename_module
    local lsp_module
    local workspace_module
    local utils_module
    local sent_messages = {}
    local send_msg_stub
    local index_stub
    local update_buf_stub
    local get_definitions_stub
    local find_r_files_stub

    -- Controls what workspace.get_definitions returns; reset in before_each.
    -- Set this in individual tests before calling rename_symbol.
    local fake_definitions = {}

    local function setup_test(content, cursor_pos)
        return test_utils.setup_lsp_test(content, cursor_pos)
    end

    local function get_last_message() return test_utils.get_last_message(sent_messages) end

    local function assert_null_response(req_id)
        local msg = get_last_message()
        assert.is_not_nil(msg, "No message was sent")
        assert.equals("N" .. req_id, msg.code)
    end

    local function assert_rename_response(req_id)
        local msg = get_last_message()
        assert.is_not_nil(msg, "No message was sent")
        assert.equals("X", msg.code)
        assert.equals(req_id, msg.orig_id)
        assert.is_not_nil(msg.changes)
        return msg
    end

    local function count_edits(changes)
        local n = 0
        for _, edits in pairs(changes) do
            n = n + #edits
        end
        return n
    end

    before_each(function()
        sent_messages = {}
        fake_definitions = {}
        package.loaded["r.lsp.rename"] = nil
        package.loaded["r.lsp.references"] = nil
        package.loaded["r.lsp.workspace"] = nil
        package.loaded["r.lsp.utils"] = nil
        package.loaded["r.lsp"] = nil
        lsp_module = require("r.lsp")
        workspace_module = require("r.lsp.workspace")
        utils_module = require("r.lsp.utils")
        rename_module = require("r.lsp.rename")
        send_msg_stub = stub(
            lsp_module,
            "send_msg",
            function(params) table.insert(sent_messages, params) end
        )
        -- Prevent actual workspace indexing
        index_stub = stub(workspace_module, "index_workspace")
        update_buf_stub = stub(workspace_module, "update_modified_buffer")
        -- Default: no cross-file definitions; individual tests can set fake_definitions
        get_definitions_stub = stub(
            workspace_module,
            "get_definitions",
            function() return fake_definitions end
        )
        -- Prevent cross-file searches from scanning the real filesystem
        find_r_files_stub = stub(utils_module, "find_r_files")
    end)

    after_each(function()
        if send_msg_stub then send_msg_stub:revert() end
        if index_stub then index_stub:revert() end
        if update_buf_stub then update_buf_stub:revert() end
        if get_definitions_stub then get_definitions_stub:revert() end
        if find_r_files_stub then find_r_files_stub:revert() end
    end)

    -- -------------------------------------------------------------------------

    describe("basic rename", function()
        it("returns null when cursor is not on an identifier", function()
            local bufnr = setup_test("x <- 42", { 1, 5 })
            if not bufnr then return end
            rename_module.rename_symbol("req1", 0, 5, bufnr, "y")
            assert_null_response("req1")
        end)

        it("renames definition and single usage", function()
            -- row=0 col=0 edge case: R parser returns "program"; put definition on row=1
            local bufnr = setup_test("dummy <- 0\nx <- 1\nprint(x)", { 2, 0 })
            if not bufnr then return end
            rename_module.rename_symbol("req2", 1, 0, bufnr, "y")
            local msg = assert_rename_response("req2")
            assert.equals(2, count_edits(msg.changes))
            for _, edits in pairs(msg.changes) do
                for _, edit in ipairs(edits) do
                    assert.equals("y", edit.newText)
                end
            end
        end)

        it("renames all occurrences", function()
            local bufnr = setup_test("dummy <- 0\nx <- 1\nz <- x + x", { 2, 0 })
            if not bufnr then return end
            rename_module.rename_symbol("req3", 1, 0, bufnr, "w")
            local msg = assert_rename_response("req3")
            assert.equals(3, count_edits(msg.changes))
            for _, edits in pairs(msg.changes) do
                for _, edit in ipairs(edits) do
                    assert.equals("w", edit.newText)
                end
            end
        end)
    end)

    -- -------------------------------------------------------------------------

    describe("named argument filtering", function()
        it("skips named argument keys", function()
            -- In ggsave(filename = filename), the first `filename` is an arg key
            -- belonging to ggsave's signature so it must not be renamed.
            -- Only the variable reference (the value) should be renamed.
            local content = 'filename <- "out.pdf"\nggsave(filename = filename)'
            local bufnr = setup_test(content, { 1, 0 })
            if not bufnr then return end
            rename_module.rename_symbol("req4", 0, 0, bufnr, "path")
            local msg = assert_rename_response("req4")
            -- definition on line 0 + value reference on line 1 = 2; arg key excluded
            assert.equals(2, count_edits(msg.changes))
            for _, edits in pairs(msg.changes) do
                for _, edit in ipairs(edits) do
                    -- arg key `filename =` starts at col 7; must never appear in edits
                    if edit.range.start.line == 1 then
                        assert.not_equals(7, edit.range.start.character)
                    end
                end
            end
        end)
    end)

    -- -------------------------------------------------------------------------

    describe("scope-aware rename", function()
        it("renames only the shadowing inner variable", function()
            local content = "x <- 100\nf <- function() {\n    x <- 200\n    print(x)\n}"
            local bufnr = setup_test(content, { 3, 4 })
            if not bufnr then return end
            -- cursor on inner `x <- 200` (row=2 0-indexed, col=4)
            rename_module.rename_symbol("req5", 2, 4, bufnr, "inner_x")
            local msg = assert_rename_response("req5")
            for _, edits in pairs(msg.changes) do
                for _, edit in ipairs(edits) do
                    assert.not_equals(
                        0,
                        edit.range.start.line,
                        "outer x on line 0 must not be renamed"
                    )
                end
            end
        end)

        it("renames outer variable including references from inner scopes", function()
            local content = "dummy <- 0\nx <- 100\nf <- function() {\n    print(x)\n}"
            local bufnr = setup_test(content, { 2, 0 })
            if not bufnr then return end
            rename_module.rename_symbol("req6", 1, 0, bufnr, "y")
            local msg = assert_rename_response("req6")
            local has_outer = false
            for _, edits in pairs(msg.changes) do
                for _, edit in ipairs(edits) do
                    if edit.range.start.line == 1 then has_outer = true end
                end
            end
            assert.is_true(has_outer, "outer definition on line 1 must be renamed")
        end)
    end)

    -- -------------------------------------------------------------------------

    describe("reassignment within same scope", function()
        it("renames all occurrences including reassignments", function()
            local content = table.concat({
                "dummy <- 0",
                "f <- function(res, pkg, pkgname, funcmeth) {",
                '  if (length(res) == 0 || (length(res) == 1 && res == "")) {',
                '    res <- ""',
                "  } else {",
                "    if (is.null(pkg)) {",
                "      info <- pkgname",
                "      if (!is.na(funcmeth)) {",
                '        if (info != "") {',
                '          info <- paste0(info, ", ")',
                "        }",
                '        info <- paste0(info, "function:", funcmeth, "()")',
                "      }",
                "    }",
                "  }",
                "}",
            }, "\n")

            -- cursor on first `info` (info <- pkgname), row=6 col=6
            local bufnr = setup_test(content, { 7, 6 })

            if not bufnr then return end

            rename_module.rename_symbol("req_reassign", 6, 6, bufnr, "detail")

            local msg = assert_rename_response("req_reassign")

            assert.equals(6, count_edits(msg.changes))

            for _, edits in pairs(msg.changes) do
                for _, edit in ipairs(edits) do
                    assert.equals("detail", edit.newText)
                end
            end
        end)
    end)

    -- -------------------------------------------------------------------------

    describe("external symbol guard", function()
        it("refuses to rename a symbol with no project definition", function()
            -- str_detect belongs to stringr; scope resolution fails and
            -- workspace.get_definitions returns nothing → rename must refuse.
            local bufnr = setup_test("str_detect(x, 'foo')", { 1, 0 })
            if not bufnr then return end
            rename_module.rename_symbol("req7", 0, 0, bufnr, "my_detect")
            assert_null_response("req7")
        end)

        it("allows rename when workspace holds a definition for the symbol", function()
            -- Simulate my_fn being defined in another project file
            fake_definitions = { { file = "/project/utils.R", line = 0, col = 0 } }
            local bufnr = setup_test("my_fn(x)", { 1, 1 })
            if not bufnr then return end
            rename_module.rename_symbol("req8", 0, 1, bufnr, "new_fn")
            assert_rename_response("req8")
        end)
    end)

    -- -------------------------------------------------------------------------

    describe("changes format", function()
        it("keys changes by file:// URI", function()
            local bufnr = setup_test("dummy <- 0\nx <- 1\nprint(x)", { 2, 0 })
            if not bufnr then return end
            rename_module.rename_symbol("req9", 1, 0, bufnr, "y")
            local msg = assert_rename_response("req9")
            for uri in pairs(msg.changes) do
                assert.is_true(
                    vim.startswith(uri, "file://"),
                    "expected file:// URI, got: " .. uri
                )
            end
        end)

        it("edits have correct range structure and newText", function()
            local bufnr = setup_test("dummy <- 0\nx <- 1\nprint(x)", { 2, 0 })
            if not bufnr then return end
            rename_module.rename_symbol("req10", 1, 0, bufnr, "y")
            local msg = assert_rename_response("req10")
            for _, edits in pairs(msg.changes) do
                for _, edit in ipairs(edits) do
                    assert.is_not_nil(edit.range)
                    assert.is_not_nil(edit.range.start)
                    assert.is_not_nil(edit.range["end"])
                    assert.is_not_nil(edit.range.start.line)
                    assert.is_not_nil(edit.range.start.character)
                    assert.equals("y", edit.newText)
                end
            end
        end)

        it("end character equals start character plus symbol length", function()
            local bufnr = setup_test("dummy <- 0\nfoo <- 1\nprint(foo)", { 2, 0 })
            if not bufnr then return end
            rename_module.rename_symbol("req11", 1, 0, bufnr, "bar")
            local msg = assert_rename_response("req11")
            for _, edits in pairs(msg.changes) do
                for _, edit in ipairs(edits) do
                    local len = edit.range["end"].character - edit.range.start.character
                    assert.equals(3, len) -- len("foo") == 3
                end
            end
        end)
    end)
end)
