local assert = require("luassert")
local stub = require("luassert.stub")
local test_utils = require("./utils")

describe("LSP workspace symbols", function()
    local symbols_module
    local workspace_module
    local lsp_module
    local sent_messages = {}
    local send_msg_stub
    local index_stub
    local find_stub

    local function get_last_message() return test_utils.get_last_message(sent_messages) end

    before_each(function()
        sent_messages = {}
        package.loaded["r.lsp.symbols"] = nil
        package.loaded["r.lsp.workspace"] = nil
        package.loaded["r.lsp"] = nil

        lsp_module = require("r.lsp")
        workspace_module = require("r.lsp.workspace")
        symbols_module = require("r.lsp.symbols")

        send_msg_stub = stub(
            lsp_module,
            "send_msg",
            function(params) table.insert(sent_messages, params) end
        )
        index_stub = stub(workspace_module, "index_workspace")
    end)

    after_each(function()
        if send_msg_stub then send_msg_stub:revert() end
        if index_stub then index_stub:revert() end
        if find_stub then
            find_stub:revert()
            find_stub = nil
        end
    end)

    describe("find_workspace_symbols", function()
        it("returns matching symbols", function()
            find_stub = stub(
                workspace_module,
                "find_workspace_symbols",
                function()
                    return {
                        {
                            name = "my_func",
                            kind = 12,
                            file = "/a.R",
                            line = 0,
                            col = 0,
                            end_col = 7,
                        },
                        {
                            name = "my_var",
                            kind = 13,
                            file = "/b.R",
                            line = 5,
                            col = 0,
                            end_col = 6,
                        },
                    }
                end
            )

            symbols_module.workspace_symbols("req1", "my")

            local msg = get_last_message()
            assert.is_not_nil(msg)
            assert.equals("W", msg.code)
            assert.equals("req1", msg.orig_id)
            assert.equals(2, #msg.symbols)
        end)

        it("sends empty array when no results", function()
            find_stub = stub(
                workspace_module,
                "find_workspace_symbols",
                function() return {} end
            )

            symbols_module.workspace_symbols("req2", "nothing")

            local msg = get_last_message()
            assert.is_not_nil(msg)
            assert.equals("W", msg.code)
            assert.equals(0, #msg.symbols)
        end)

        it("sends empty array for empty query", function()
            find_stub = stub(workspace_module, "find_workspace_symbols", function(q)
                assert.equals("", q)
                return {}
            end)

            symbols_module.workspace_symbols("req3", "")
            local msg = get_last_message()
            assert.equals("W", msg.code)
            assert.equals(0, #msg.symbols)
        end)

        it("formats symbols with correct LSP fields", function()
            find_stub = stub(
                workspace_module,
                "find_workspace_symbols",
                function()
                    return {
                        {
                            name = "foo",
                            kind = 12,
                            file = "/proj/foo.R",
                            line = 3,
                            col = 0,
                            end_col = 3,
                        },
                    }
                end
            )

            symbols_module.workspace_symbols("req4", "foo")

            local msg = get_last_message()
            local sym = msg.symbols[1]
            assert.equals("foo", sym.name)
            assert.equals(12, sym.kind)
            assert.is_not_nil(sym.location)
            assert.is_not_nil(sym.location.uri)
            assert.equals(3, sym.location.range.start.line)
            assert.equals(0, sym.location.range.start.character)
            assert.equals(3, sym.location.range["end"].character)
        end)

        it("defaults nil query to empty string", function()
            local captured_query
            find_stub = stub(workspace_module, "find_workspace_symbols", function(q)
                captured_query = q
                return {}
            end)

            symbols_module.workspace_symbols("req5", nil)
            assert.equals("", captured_query)
        end)
    end)

    describe("find_workspace_symbols (workspace module, real index)", function()
        local tmpfile
        local find_files_stub
        local utils_module

        before_each(function()
            -- Revert the outer index_stub so real indexing runs
            if index_stub then
                index_stub:revert()
                index_stub = nil
            end

            -- Write a temp R file with known symbols
            tmpfile = vim.fn.tempname() .. ".R"
            vim.fn.writefile({
                "MyFunc <- function(x) { x + 1 }",
                "my_var <- 42",
                "other_func <- function() {}",
            }, tmpfile)

            -- Reload workspace so its internal state is clean
            package.loaded["r.lsp.workspace"] = nil
            utils_module = require("r.lsp.utils")

            -- Stub find_r_files to only return our controlled file
            find_files_stub = stub(
                utils_module,
                "find_r_files",
                function(_, files) table.insert(files, tmpfile) end
            )

            workspace_module = require("r.lsp.workspace")
        end)

        after_each(function()
            if find_files_stub then find_files_stub:revert() end
            if tmpfile then vim.fn.delete(tmpfile) end
            package.loaded["r.lsp.workspace"] = nil
        end)

        local function index()
            local ok = pcall(vim.treesitter.language.add, "r")
            if not ok then
                pending("treesitter parser for R not available")
                return false
            end
            workspace_module.rebuild_index()
            return true
        end

        it("matches case-insensitively", function()
            if not index() then return end
            local results = workspace_module.find_workspace_symbols("myfunc")
            local names = vim.tbl_map(function(r) return r.name end, results)
            assert.is_truthy(vim.tbl_contains(names, "MyFunc"))
        end)

        it("returns all symbols on empty query", function()
            if not index() then return end
            local results = workspace_module.find_workspace_symbols("")
            assert.is_true(#results >= 2)
        end)

        it("returns empty for no match", function()
            if not index() then return end
            local results = workspace_module.find_workspace_symbols("zzznomatch")
            assert.equals(0, #results)
        end)

        it("matches substring", function()
            if not index() then return end
            local results = workspace_module.find_workspace_symbols("func")
            local names = vim.tbl_map(function(r) return r.name end, results)
            assert.is_truthy(vim.tbl_contains(names, "MyFunc"))
            assert.is_truthy(vim.tbl_contains(names, "other_func"))
        end)

        it("includes kind and location fields", function()
            if not index() then return end
            local results = workspace_module.find_workspace_symbols("MyFunc")
            assert.equals(1, #results)
            local r = results[1]
            assert.equals("MyFunc", r.name)
            assert.equals(12, r.kind)
            assert.is_string(r.file)
            assert.is_number(r.line)
            assert.is_number(r.col)
            assert.is_number(r.end_col)
        end)
    end)
end)
