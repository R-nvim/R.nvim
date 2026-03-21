local assert = require("luassert")
local stub = require("luassert.stub")
local test_utils = require("./utils")

describe("LSP textDocument/documentHighlight", function()
    local highlight_module
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

    local function assert_highlight_response(req_id)
        local msg = get_last_message()
        assert.is_not_nil(msg, "No message was sent")
        assert.equals("L", msg.code)
        assert.equals(req_id, msg.orig_id)
        assert.is_not_nil(msg.highlights)
        return msg
    end

    before_each(function()
        sent_messages = {}
        package.loaded["r.lsp.highlight"] = nil
        package.loaded["r.lsp"] = nil
        lsp_module = require("r.lsp")
        highlight_module = require("r.lsp.highlight")
        send_msg_stub = stub(
            lsp_module,
            "send_msg",
            function(params) table.insert(sent_messages, params) end
        )
    end)

    after_each(function()
        if send_msg_stub then send_msg_stub:revert() end
    end)

    describe("basic highlights", function()
        it("highlights all occurrences of a variable", function()
            -- cursor on x in "y <- x + x" (row=1, col=5); avoids (row=0,col=0) edge case
            local bufnr = setup_test("x <- 1\ny <- x + x", { 2, 5 })
            if not bufnr then return end
            highlight_module.document_highlight("req1", 1, 5, bufnr)
            local msg = assert_highlight_response("req1")
            -- x: definition on line 0, two uses on line 1
            assert.equals(3, #msg.highlights)
        end)

        it("returns null when cursor is on a number literal", function()
            -- col 5 is the '4' in '42', not an identifier
            local bufnr = setup_test("x <- 42", { 1, 5 })
            if not bufnr then return end
            highlight_module.document_highlight("req2", 0, 5, bufnr)
            assert_null_response("req2")
        end)
    end)

    describe("read/write kind classification", function()
        it("classifies assignment target as Write (kind=3)", function()
            -- x on row 1 (0-indexed) avoids the (row=0,col=0) program-node edge case
            local bufnr = setup_test("y <- 0\nx <- 1", { 2, 0 })
            if not bufnr then return end
            highlight_module.document_highlight("req3", 1, 0, bufnr)
            local msg = assert_highlight_response("req3")
            assert.equals(1, #msg.highlights)
            assert.equals(3, msg.highlights[1].kind) -- Write
        end)

        it("classifies variable use as Read (kind=2)", function()
            -- cursor on x in print(x): "print(" is 6 chars so x is at col 6
            local bufnr = setup_test("x <- 1\nprint(x)", { 2, 6 })
            if not bufnr then return end
            highlight_module.document_highlight("req4", 1, 6, bufnr)
            local msg = assert_highlight_response("req4")
            local found_read = false
            for _, h in ipairs(msg.highlights) do
                if h.range.start.line == 1 then
                    assert.equals(2, h.kind) -- Read
                    found_read = true
                end
            end
            assert.is_true(found_read, "Expected a Read highlight on line 1")
        end)

        it("classifies right-arrow assignment target as Write (kind=3)", function()
            -- x is at col 5 in "1 -> x", safely away from (row=0,col=0)
            local bufnr = setup_test("1 -> x", { 1, 5 })
            if not bufnr then return end
            highlight_module.document_highlight("req5", 0, 5, bufnr)
            local msg = assert_highlight_response("req5")
            assert.equals(1, #msg.highlights)
            assert.equals(3, msg.highlights[1].kind) -- Write
        end)

        it("classifies super-assignment (<<-) target as Write (kind=3)", function()
            -- x is at col 18 in "f <- function() { x <<- 10 }"
            local bufnr = setup_test("f <- function() { x <<- 10 }", { 1, 18 })
            if not bufnr then return end
            highlight_module.document_highlight("req6", 0, 18, bufnr)
            local msg = assert_highlight_response("req6")
            assert.equals(1, #msg.highlights)
            assert.equals(3, msg.highlights[1].kind) -- Write
        end)
    end)

    describe("compound assignment targets", function()
        it("classifies index assignment x[1] <- val as Write (kind=3)", function()
            -- cursor on x in "x[1] <- 99" on row 1 (0-indexed)
            local bufnr = setup_test("x <- c(1,2,3)\nx[1] <- 99", { 2, 0 })
            if not bufnr then return end
            highlight_module.document_highlight("req7", 1, 0, bufnr)
            local msg = assert_highlight_response("req7")
            local write_count = 0
            for _, h in ipairs(msg.highlights) do
                if h.kind == 3 then write_count = write_count + 1 end
            end
            assert.is_true(write_count >= 1, "Expected at least one Write highlight")
        end)

        it("classifies dollar assignment x$y <- val as Write (kind=3)", function()
            local bufnr = setup_test("x <- list()\nx$y <- 5", { 2, 0 })
            if not bufnr then return end
            highlight_module.document_highlight("req8", 1, 0, bufnr)
            local msg = assert_highlight_response("req8")
            local write_count = 0
            for _, h in ipairs(msg.highlights) do
                if h.kind == 3 then write_count = write_count + 1 end
            end
            assert.is_true(write_count >= 1, "Expected at least one Write highlight")
        end)

        it("classifies replacement function names(x) <- val as Write (kind=3)", function()
            -- x inside names(x) is at col 6 on row 1
            local bufnr = setup_test("x <- c(1,2)\nnames(x) <- c('a','b')", { 2, 6 })
            if not bufnr then return end
            highlight_module.document_highlight("req9", 1, 6, bufnr)
            local msg = assert_highlight_response("req9")
            local write_count = 0
            for _, h in ipairs(msg.highlights) do
                if h.kind == 3 then write_count = write_count + 1 end
            end
            assert.is_true(write_count >= 1, "Expected at least one Write highlight")
        end)
    end)

    describe("scope-aware filtering", function()
        it("highlights only in-scope definition when variable is shadowed", function()
            local content = [[
x <- 100
f <- function() {
    x <- 200
    print(x)
}]]
            -- cursor on inner x in "    x <- 200" (row=3 1-indexed = row=2 0-indexed, col=4)
            local bufnr = setup_test(content, { 3, 4 })
            if not bufnr then return end
            highlight_module.document_highlight("req10", 2, 4, bufnr)
            local msg = assert_highlight_response("req10")
            for _, h in ipairs(msg.highlights) do
                assert.not_equals(0, h.range.start.line)
            end
        end)

        it("highlights outer variable when referenced from inner scope", function()
            local content = [[
x <- 100
f <- function() {
    print(x)
}]]
            -- cursor on x in "    print(x)" (row=3 1-indexed = row=2 0-indexed, col=10)
            local bufnr = setup_test(content, { 3, 10 })
            if not bufnr then return end
            highlight_module.document_highlight("req11", 2, 10, bufnr)
            local msg = assert_highlight_response("req11")
            local has_outer = false
            for _, h in ipairs(msg.highlights) do
                if h.range.start.line == 0 then has_outer = true end
            end
            assert.is_true(has_outer, "Expected outer x on line 0 to be highlighted")
        end)

        it("highlights all occurrences when symbol has no definition in scope", function()
            -- z is never defined; scope resolution returns nil so all occurrences are highlighted
            local bufnr = setup_test("print(z)\ncat(z)", { 1, 6 })
            if not bufnr then return end
            highlight_module.document_highlight("req12", 0, 6, bufnr)
            local msg = assert_highlight_response("req12")
            assert.equals(2, #msg.highlights)
        end)
    end)
end)
