local assert = require("luassert")
local stub = require("luassert.stub")
local test_utils = require("./utils")

describe("LSP find-implementations", function()
    local impl_module
    local lsp_module
    local workspace_module
    local sent_messages = {}
    local send_msg_stub
    local find_symbols_stub
    local index_stub
    local update_buf_stub

    local function setup_test(content, cursor_pos)
        local bufnr = test_utils.create_r_buffer_from_string(content, "r")
        vim.api.nvim_set_current_buf(bufnr)
        vim.api.nvim_win_set_cursor(0, cursor_pos)
        vim.treesitter.language.add("r")
        local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "r")
        if not ok or not parser then
            pending("treesitter parser for R is not available")
            return nil
        end
        parser:parse()
        return bufnr
    end

    local function get_last_message() return sent_messages[#sent_messages] end

    before_each(function()
        sent_messages = {}
        package.loaded["r.lsp.implementation"] = nil
        package.loaded["r.lsp.workspace"] = nil
        package.loaded["r.lsp"] = nil

        lsp_module = require("r.lsp")
        workspace_module = require("r.lsp.workspace")
        impl_module = require("r.lsp.implementation")

        send_msg_stub = stub(
            lsp_module,
            "send_msg",
            function(params) table.insert(sent_messages, params) end
        )
        index_stub = stub(workspace_module, "index_workspace")
        update_buf_stub = stub(workspace_module, "update_modified_buffer")
    end)

    after_each(function()
        if send_msg_stub then send_msg_stub:revert() end
        if index_stub then index_stub:revert() end
        if update_buf_stub then update_buf_stub:revert() end
        if find_symbols_stub then
            find_symbols_stub:revert()
            find_symbols_stub = nil
        end
    end)

    it("finds S3 method implementations", function()
        setup_test("print(x)", { 1, 0 })

        find_symbols_stub = stub(
            workspace_module,
            "find_symbols_matching",
            function()
                return {
                    { file = "/tmp/a.R", line = 5, col = 0 },
                    { file = "/tmp/b.R", line = 12, col = 0 },
                }
            end
        )

        impl_module.find_implementations("req1")

        local msg = get_last_message()
        assert.is_not_nil(msg)
        assert.equals("I", msg.code)
        assert.equals("req1", msg.orig_id)
        assert.equals(2, #msg.locations)
    end)

    it("builds correct S3 pattern", function()
        setup_test("summary(x)", { 1, 0 })

        local captured_pattern
        find_symbols_stub = stub(
            workspace_module,
            "find_symbols_matching",
            function(pattern)
                captured_pattern = pattern
                return {}
            end
        )

        impl_module.find_implementations("req2")

        assert.is_not_nil(captured_pattern)
        -- Pattern should match "summary.foo" but not "summary_foo" or "xsummary.foo"
        assert.is_truthy(string.match("summary.default", captured_pattern))
        assert.is_truthy(string.match("summary.lm", captured_pattern))
        assert.is_falsy(string.match("summary_lm", captured_pattern))
        assert.is_falsy(string.match("xsummary.lm", captured_pattern))
    end)

    it("sends null when no implementations found", function()
        setup_test("myfunc(x)", { 1, 0 })

        find_symbols_stub = stub(
            workspace_module,
            "find_symbols_matching",
            function() return {} end
        )

        impl_module.find_implementations("req3")

        local msg = get_last_message()
        assert.is_not_nil(msg)
        assert.equals("Nreq3", msg.code)
    end)

    it("sends null on empty cursor", function()
        setup_test("", { 1, 0 })
        impl_module.find_implementations("req4")

        local msg = get_last_message()
        assert.is_not_nil(msg)
        assert.equals("Nreq4", msg.code)
    end)
end)

