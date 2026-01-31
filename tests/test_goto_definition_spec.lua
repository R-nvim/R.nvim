local assert = require("luassert")
local stub = require("luassert.stub")
local test_utils = require("./utils")

describe("LSP goto-definition", function()
    local definition_module
    local lsp_module
    local sent_messages = {}
    local send_msg_stub

    local function setup_test(content, cursor_pos)
        return test_utils.setup_lsp_test(content, cursor_pos)
    end

    local function get_last_message() return test_utils.get_last_message(sent_messages) end

    local function assert_null_response(req_id)
        local msg = get_last_message()
        assert.is_not_nil(msg, "No message was sent")
        assert.equals("N" .. req_id, msg.code)
    end

    local function assert_location_response(req_id, expected_line, expected_col)
        local msg = get_last_message()
        assert.is_not_nil(msg, "No message was sent")
        assert.equals("D", msg.code)
        assert.equals(req_id, msg.orig_id)
        if expected_line then assert.equals(expected_line, msg.line) end
        if expected_col then assert.equals(expected_col, msg.col) end
        return msg
    end

    before_each(function()
        sent_messages = {}
        package.loaded["r.lsp.definition"] = nil
        package.loaded["r.lsp.workspace"] = nil
        package.loaded["r.lsp"] = nil
        lsp_module = require("r.lsp")
        definition_module = require("r.lsp.definition")
        send_msg_stub = stub(
            lsp_module,
            "send_msg",
            function(params) table.insert(sent_messages, params) end
        )
        vim.g.R_Nvim_status = 0
    end)

    after_each(function()
        if send_msg_stub then send_msg_stub:revert() end
    end)

    describe("basic definitions", function()
        it("finds variable definition", function()
            setup_test("x <- 42\ny <- x", { 2, 5 })
            definition_module.goto_definition("req1")
            assert_location_response("req1", 0, 0)
        end)

        it("finds function definition", function()
            setup_test(
                "my_func <- function(a) { a + 1 }\nresult <- my_func(1)",
                { 2, 10 }
            )
            definition_module.goto_definition("req2")
            assert_location_response("req2", 0, 0)
        end)

        it("returns null when symbol not found", function()
            setup_test("x <- 42\nundefined_symbol", { 2, 0 })
            definition_module.goto_definition("req3")
            assert_null_response("req3")
        end)
    end)

    describe("scope-aware resolution", function()
        it("finds parameter in function scope", function()
            setup_test("f <- function(param) {\n    result <- param + 1\n}", { 2, 14 })
            definition_module.goto_definition("req4")
            assert_location_response("req4", 0, 14)
        end)

        it("inner scope shadows outer", function()
            local content = [[
x <- 100
outer <- function() {
    x <- 200
    print(x)
}]]
            setup_test(content, { 4, 10 })
            definition_module.goto_definition("req5")
            assert_location_response("req5", 2, 4)
        end)

        it("searches outer scopes when not found in inner", function()
            local content = [[
x <- 100
f <- function(y) {
    z <- x + y
}]]
            setup_test(content, { 3, 9 })
            definition_module.goto_definition("req6")
            assert_location_response("req6", 0, 0)
        end)

        it("handles nested function definitions", function()
            local content = [[
outer <- function() {
    helper <- function(x) { x * 2 }
    result <- helper(10)
}]]
            setup_test(content, { 3, 14 })
            definition_module.goto_definition("req7")
            assert_location_response("req7", 1, 4)
        end)
    end)

    describe("edge cases", function()
        it("handles empty buffer", function()
            setup_test("", { 1, 0 })
            definition_module.goto_definition("req8")
            assert_null_response("req8")
        end)

        it("handles symbols with dots and underscores", function()
            setup_test("my.var_name <- 100\nresult <- my.var_name", { 2, 10 })
            definition_module.goto_definition("req9")
            assert_location_response("req9", 0, 0)
        end)
    end)
end)
