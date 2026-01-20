local assert = require("luassert")
local test_utils = require("./utils")

describe("Scope module", function()
    local scope_module

    -- Helper to setup test buffer with cursor position
    local function setup_test(content, cursor_pos)
        local bufnr = test_utils.create_r_buffer_from_string(content, "r")
        vim.api.nvim_set_current_buf(bufnr)
        if cursor_pos then vim.api.nvim_win_set_cursor(0, cursor_pos) end

        -- Ensure treesitter parser is loaded
        vim.treesitter.language.add("r")
        local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "r")
        if not ok or not parser then
            pending("treesitter parser for R is not available")
            return nil
        end
        parser:parse()

        return bufnr
    end

    before_each(function()
        package.loaded["r.lsp.scope"] = nil
        scope_module = require("r.lsp.scope")
    end)

    describe("get_scope_at_position", function()
        it("returns scope context for position in file scope", function()
            local content = [[
x <- 42
y <- x + 1
]]
            local bufnr = setup_test(content, { 1, 0 })
            local scope = scope_module.get_scope_at_position(bufnr, 0, 0)

            assert.is_not_nil(scope, "Scope should not be nil")
            assert.equals(bufnr, scope.bufnr)
            assert.equals(0, scope.row)
            assert.equals(0, scope.col)
            assert.is_table(scope.scope_nodes)
            assert.is_true(#scope.scope_nodes > 0, "Should have at least root scope")
        end)

        it("returns scope context for position inside function", function()
            local content = [[
my_func <- function(x) {
    y <- x + 1
    return(y)
}
]]
            local bufnr = setup_test(content, { 2, 4 })
            local scope = scope_module.get_scope_at_position(bufnr, 1, 4) -- 0-indexed

            assert.is_not_nil(scope)
            assert.is_table(scope.scope_nodes)
            -- Should have at least 2 scopes: function scope and root scope
            assert.is_true(#scope.scope_nodes >= 2)
        end)

        it("returns scope context for nested functions", function()
            local content = [[
outer <- function() {
    inner <- function(x) {
        z <- x * 2
        return(z)
    }
    return(inner)
}
]]
            local bufnr = setup_test(content, { 3, 8 })
            local scope = scope_module.get_scope_at_position(bufnr, 2, 8) -- inside inner function

            assert.is_not_nil(scope)
            assert.is_table(scope.scope_nodes)
            -- Should have 3 scopes: inner function, outer function, root
            assert.is_true(
                #scope.scope_nodes >= 3,
                "Expected at least 3 scopes for nested function"
            )
        end)

        it("returns nil for invalid buffer", function()
            local scope = scope_module.get_scope_at_position(9999, 0, 0)
            -- May return nil or empty scope_nodes depending on implementation
            assert.is_true(scope == nil or #scope.scope_nodes == 0)
        end)

        it("handles position at end of file", function()
            local content = [[
x <- 42
]]
            local bufnr = setup_test(content, { 1, 7 })
            local scope = scope_module.get_scope_at_position(bufnr, 0, 7)

            assert.is_not_nil(scope)
        end)
    end)

    describe("resolve_symbol", function()
        it("resolves symbol at file level", function()
            local content = [[
global_var <- 100
x <- global_var + 1
]]
            local bufnr = setup_test(content, { 2, 5 })
            local scope = scope_module.get_scope_at_position(bufnr, 1, 5)
            local def = scope_module.resolve_symbol("global_var", scope)

            assert.is_not_nil(def, "Definition should be found")
            assert.equals("global_var", def.name)
            assert.is_not_nil(def.location)
            assert.equals(0, def.location.line) -- first line (0-indexed)
            assert.equals("public", def.visibility) -- file-level definition
        end)

        it("resolves function parameter", function()
            local content = [[
my_func <- function(param1, param2) {
    result <- param1 + param2
    return(result)
}
]]
            local bufnr = setup_test(content, { 2, 14 })
            local scope = scope_module.get_scope_at_position(bufnr, 1, 14)
            local def = scope_module.resolve_symbol("param1", scope)

            assert.is_not_nil(def)
            assert.equals("param1", def.name)
            assert.equals("parameter", def.visibility)
            assert.equals(0, def.location.line) -- parameters on first line
        end)

        it("resolves local variable in function", function()
            local content = [[
my_func <- function(x) {
    local_var <- x * 2
    result <- local_var + 1
    return(result)
}
]]
            local bufnr = setup_test(content, { 3, 14 })
            local scope = scope_module.get_scope_at_position(bufnr, 2, 14)
            local def = scope_module.resolve_symbol("local_var", scope)

            assert.is_not_nil(def)
            assert.equals("local_var", def.name)
            assert.equals("private", def.visibility)
            assert.equals(1, def.location.line) -- second line (0-indexed)
        end)

        it("resolves through scope chain (outer variable from inner function)", function()
            local content = [[
x <- 100
my_func <- function(y) {
    z <- x + y
    return(z)
}
]]
            local bufnr = setup_test(content, { 3, 9 })
            local scope = scope_module.get_scope_at_position(bufnr, 2, 9)
            local def = scope_module.resolve_symbol("x", scope)

            assert.is_not_nil(def, "Should find 'x' in outer scope")
            assert.equals("x", def.name)
            assert.equals(0, def.location.line)
            assert.equals("public", def.visibility) -- file-level
        end)

        it("handles variable shadowing (inner scope wins)", function()
            local content = [[
x <- 100
outer <- function() {
    x <- 200
    inner <- function() {
        x <- 300
        result <- x
    }
}
]]
            local bufnr = setup_test(content, { 6, 18 })
            local scope = scope_module.get_scope_at_position(bufnr, 5, 18)
            local def = scope_module.resolve_symbol("x", scope)

            assert.is_not_nil(def)
            assert.equals("x", def.name)
            -- Should find the innermost definition (line 5, 0-indexed = line 4)
            assert.equals(4, def.location.line)
        end)

        it("returns nil for undefined symbol", function()
            local content = [[
x <- 42
y <- x + 1
]]
            local bufnr = setup_test(content, { 2, 0 })
            local scope = scope_module.get_scope_at_position(bufnr, 1, 0)
            local def = scope_module.resolve_symbol("undefined_symbol", scope)

            assert.is_nil(def)
        end)

        it("handles nested function scopes correctly", function()
            local content = [[
outer <- function() {
    helper <- function(x) {
        return(x * 2)
    }
    result <- helper(10)
}
]]
            local bufnr = setup_test(content, { 5, 14 })
            local scope = scope_module.get_scope_at_position(bufnr, 4, 14)
            local def = scope_module.resolve_symbol("helper", scope)

            assert.is_not_nil(def)
            assert.equals("helper", def.name)
            assert.equals(1, def.location.line) -- helper defined on line 2
        end)

        it("resolves function definitions", function()
            local content = [[
my_func <- function(x) {
    x + 1
}
result <- my_func(10)
]]
            local bufnr = setup_test(content, { 4, 10 })
            local scope = scope_module.get_scope_at_position(bufnr, 3, 10)
            local def = scope_module.resolve_symbol("my_func", scope)

            assert.is_not_nil(def)
            assert.equals("my_func", def.name)
            assert.equals(12, def.kind) -- Function kind
            assert.equals(0, def.location.line)
        end)

        it("handles multiple parameters", function()
            local content = [[
my_func <- function(a, b, c) {
    result <- a + b + c
}
]]
            local bufnr = setup_test(content, { 2, 14 })
            local scope = scope_module.get_scope_at_position(bufnr, 1, 14)

            -- Test resolving each parameter
            local def_a = scope_module.resolve_symbol("a", scope)
            local def_b = scope_module.resolve_symbol("b", scope)
            local def_c = scope_module.resolve_symbol("c", scope)

            assert.is_not_nil(def_a)
            assert.is_not_nil(def_b)
            assert.is_not_nil(def_c)
            assert.equals("parameter", def_a.visibility)
            assert.equals("parameter", def_b.visibility)
            assert.equals("parameter", def_c.visibility)
        end)

        it("does not find parameters at file scope", function()
            local content = [[
my_func <- function(param1) {
    x <- param1
}
# Try to use param1 here
y <- param1
]]
            local bufnr = setup_test(content, { 5, 5 })
            -- Get scope at file level (outside function)
            local scope = scope_module.get_scope_at_position(bufnr, 4, 5)
            local def = scope_module.resolve_symbol("param1", scope)

            -- Should not find param1 at file scope
            assert.is_nil(def)
        end)
    end)

    describe("Symbol kinds and visibility", function()
        it("correctly identifies function definitions", function()
            local content = [[
my_func <- function() {
    42
}
]]
            local bufnr = setup_test(content, { 1, 0 })
            local scope = scope_module.get_scope_at_position(bufnr, 0, 0)
            local def = scope_module.resolve_symbol("my_func", scope)

            assert.is_not_nil(def)
            assert.equals(12, def.kind) -- Function
        end)

        it("correctly identifies variable definitions", function()
            local content = [[
my_var <- 42
]]
            local bufnr = setup_test(content, { 1, 0 })
            local scope = scope_module.get_scope_at_position(bufnr, 0, 0)
            local def = scope_module.resolve_symbol("my_var", scope)

            assert.is_not_nil(def)
            assert.equals(13, def.kind) -- Variable
        end)

        it("marks file-level symbols as public", function()
            local content = [[
public_var <- 100
]]
            local bufnr = setup_test(content, { 1, 0 })
            local scope = scope_module.get_scope_at_position(bufnr, 0, 0)
            local def = scope_module.resolve_symbol("public_var", scope)

            assert.is_not_nil(def)
            assert.equals("public", def.visibility)
        end)

        it("marks function-level symbols as private", function()
            local content = [[
my_func <- function() {
    private_var <- 100
}
]]
            local bufnr = setup_test(content, { 2, 4 })
            local scope = scope_module.get_scope_at_position(bufnr, 1, 4)
            local def = scope_module.resolve_symbol("private_var", scope)

            assert.is_not_nil(def)
            assert.equals("private", def.visibility)
        end)
    end)

    describe("Edge cases", function()
        it("handles nil scope context", function()
            local def = scope_module.resolve_symbol("any_symbol", nil)
            assert.is_nil(def)
        end)

        it("handles scope context with no scope_nodes", function()
            local fake_scope = {
                bufnr = 1,
                row = 0,
                col = 0,
                scope_nodes = {},
            }
            local def = scope_module.resolve_symbol("any_symbol", fake_scope)
            assert.is_nil(def)
        end)

        it("handles symbols with dots", function()
            local content = [[
my.var <- 100
x <- my.var + 1
]]
            local bufnr = setup_test(content, { 2, 5 })
            local scope = scope_module.get_scope_at_position(bufnr, 1, 5)
            local def = scope_module.resolve_symbol("my.var", scope)

            assert.is_not_nil(def)
            assert.equals("my.var", def.name)
        end)

        it("handles symbols with underscores", function()
            local content = [[
my_var <- 100
x <- my_var + 1
]]
            local bufnr = setup_test(content, { 2, 5 })
            local scope = scope_module.get_scope_at_position(bufnr, 1, 5)
            local def = scope_module.resolve_symbol("my_var", scope)

            assert.is_not_nil(def)
            assert.equals("my_var", def.name)
        end)

        it("handles empty function bodies", function()
            local content = [[
empty_func <- function() {
}
]]
            local bufnr = setup_test(content, { 2, 0 })
            local scope = scope_module.get_scope_at_position(bufnr, 1, 0)

            assert.is_not_nil(scope)
            -- Should still have scope even if function is empty
            assert.is_table(scope.scope_nodes)
        end)

        it("handles very deeply nested functions", function()
            local content = [[
f1 <- function() {
    f2 <- function() {
        f3 <- function() {
            f4 <- function() {
                x <- 42
                return(x)
            }
        }
    }
}
]]
            local bufnr = setup_test(content, { 6, 16 })
            local scope = scope_module.get_scope_at_position(bufnr, 5, 16)

            assert.is_not_nil(scope)
            -- Should have multiple nested scopes
            assert.is_true(#scope.scope_nodes >= 4)

            local def = scope_module.resolve_symbol("x", scope)
            assert.is_not_nil(def)
        end)
    end)
end)

