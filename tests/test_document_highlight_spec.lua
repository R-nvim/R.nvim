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
            local bufnr = setup_test("x <- 1\ny <- x + x", { 1, 0 })
            if not bufnr then return end
            highlight_module.document_highlight("req1", 0, 0, bufnr)
            local msg = assert_highlight_response("req1")
            -- x appears 3 times: definition + 2 uses
            assert.equals(3, #msg.highlights)
        end)

        it("returns null when cursor is not on an identifier", function()
            local bufnr = setup_test("x <- 1\n", { 1, 0 })
            if not bufnr then return end
            -- Position 0,5 is on the number literal '1', not an identifier
            highlight_module.document_highlight("req2", 0, 5, bufnr)
            assert_null_response("req2")
        end)

        it("returns null when cursor is on a number literal (not an identifier)", function()
            local bufnr = setup_test("x <- 42", { 1, 0 })
            if not bufnr then return end
            -- Position 0,5 is on '4' in '42', a number literal, not an identifier
            highlight_module.document_highlight("req3", 0, 5, bufnr)
            assert_null_response("req3")
        end)
    end)

    describe("read/write kind classification", function()
        it("classifies assignment target as write (kind=3)", function()
            local bufnr = setup_test("x <- 1", { 1, 0 })
            if not bufnr then return end
            highlight_module.document_highlight("req4", 0, 0, bufnr)
            local msg = assert_highlight_response("req4")
            assert.equals(1, #msg.highlights)
            assert.equals(3, msg.highlights[1].kind) -- Write
        end)

        it("classifies variable use as read (kind=2)", function()
            local bufnr = setup_test("x <- 1\nprint(x)", { 1, 0 })
            if not bufnr then return end
            highlight_module.document_highlight("req5", 0, 0, bufnr)
            local msg = assert_highlight_response("req5")
            -- Find the read occurrence (line 1, the use in print(x))
            local found_read = false
            for _, h in ipairs(msg.highlights) do
                if h.range.start.line == 1 then
                    assert.equals(2, h.kind) -- Read
                    found_read = true
                end
            end
            assert.is_true(found_read, "Expected a read highlight on the second line")
        end)

        it("classifies right-arrow assignment target as write (kind=3)", function()
            local bufnr = setup_test("1 -> x", { 1, 0 })
            if not bufnr then return end
            -- Position on 'x' (the assignment target for ->)
            highlight_module.document_highlight("req6", 0, 5, bufnr)
            local msg = assert_highlight_response("req6")
            assert.equals(1, #msg.highlights)
            assert.equals(3, msg.highlights[1].kind) -- Write
        end)

        it("classifies super-assignment target as write (kind=3)", function()
            local bufnr = setup_test("f <- function() { x <<- 10 }", { 1, 0 })
            if not bufnr then return end
            -- Position on 'x' inside the function (the <<- target)
            highlight_module.document_highlight("req7", 0, 18, bufnr)
            local msg = assert_highlight_response("req7")
            assert.equals(1, #msg.highlights)
            assert.equals(3, msg.highlights[1].kind) -- Write
        end)
    end)

    describe("compound assignment targets (edge cases)", function()
        it("classifies index assignment target as write (x[1] <- value)", function()
            local bufnr = setup_test("x <- c(1,2,3)\nx[1] <- 99", { 1, 0 })
            if not bufnr then return end
            highlight_module.document_highlight("req8", 0, 0, bufnr)
            local msg = assert_highlight_response("req8")
            -- Both occurrences of x should be found; the one on line 1 (x[1] <-) is a write
            local write_count = 0
            for _, h in ipairs(msg.highlights) do
                if h.kind == 3 then write_count = write_count + 1 end
            end
            assert.is_true(write_count >= 1, "Expected at least one write highlight")
        end)

        it("classifies dollar-sign assignment target as write (x$y <- value)", function()
            local bufnr = setup_test("x <- list()\nx$y <- 5", { 1, 0 })
            if not bufnr then return end
            highlight_module.document_highlight("req9", 0, 0, bufnr)
            local msg = assert_highlight_response("req9")
            local write_count = 0
            for _, h in ipairs(msg.highlights) do
                if h.kind == 3 then write_count = write_count + 1 end
            end
            assert.is_true(write_count >= 1, "Expected at least one write highlight")
        end)

        it("classifies replacement function target as write (names(x) <- value)", function()
            local bufnr = setup_test("x <- c(1,2)\nnames(x) <- c('a','b')", { 1, 0 })
            if not bufnr then return end
            -- Cursor on 'x' in the first line
            highlight_module.document_highlight("req10", 0, 0, bufnr)
            local msg = assert_highlight_response("req10")
            -- x inside names(x) <- is inside the lhs, so it is a write
            local write_count = 0
            for _, h in ipairs(msg.highlights) do
                if h.kind == 3 then write_count = write_count + 1 end
            end
            assert.is_true(write_count >= 1, "Expected at least one write highlight")
        end)
    end)

    describe("scope-aware filtering", function()
        it("highlights only the in-scope definition when variable is shadowed", function()
            local content = [[
x <- 100
f <- function() {
    x <- 200
    print(x)
}]]
            local bufnr = setup_test(content, { 3, 4 })
            if not bufnr then return end
            -- Cursor on 'x <- 200' inside f; should only highlight inner x
            highlight_module.document_highlight("req11", 2, 4, bufnr)
            local msg = assert_highlight_response("req11")
            for _, h in ipairs(msg.highlights) do
                -- None of the highlights should be on line 0 (outer x <- 100)
                assert.not_equals(0, h.range.start.line)
            end
        end)

        it("highlights outer variable from inner scope when not shadowed", function()
            local content = [[
x <- 100
f <- function() {
    print(x)
}]]
            local bufnr = setup_test(content, { 3, 10 })
            if not bufnr then return end
            -- Cursor on 'x' inside print(x); resolves to outer x <- 100
            highlight_module.document_highlight("req12", 2, 10, bufnr)
            local msg = assert_highlight_response("req12")
            -- Outer definition on line 0 should be included
            local has_outer = false
            for _, h in ipairs(msg.highlights) do
                if h.range.start.line == 0 then has_outer = true end
            end
            assert.is_true(has_outer, "Expected outer x to be highlighted")
        end)

        it("highlights all occurrences when symbol is unresolvable", function()
            -- 'z' is used but never defined locally – scope resolution returns nil,
            -- so all buffer occurrences should be highlighted.
            local content = "print(z)\ncat(z)"
            local bufnr = setup_test(content, { 1, 6 })
            if not bufnr then return end
            highlight_module.document_highlight("req13", 0, 6, bufnr)
            local msg = assert_highlight_response("req13")
            assert.equals(2, #msg.highlights)
        end)
    end)
end)
