--- Lintr diagnostics for R.nvim
--- This module provides lintr integration for R files using a persistent R subprocess.

local M = {}

local config = require("r.config").get_config
local warn = require("r.log").warn

-- Namespace for diagnostics
local ns = vim.api.nvim_create_namespace("r_lintr")

-- Worker state
local worker = nil
local pending = {} -- pending requests by request_id
local debounce_timers = {} -- debounce timers by bufnr
local request_id = 0

-- Severity mapping: lintr type -> vim.diagnostic.severity
local severity_map = {
    error = vim.diagnostic.severity.ERROR,
    warning = vim.diagnostic.severity.WARN,
    style = vim.diagnostic.severity.INFO,
}

-- R code for the persistent lintr worker, maybe import the code as a separate file later?
local worker_r_code = [==[
suppressPackageStartupMessages({
    if (!requireNamespace("lintr", quietly = TRUE)) {
        cat('{"error": "lintr package not installed"}\n')
        quit(save = "no", status = 1)
    }
    if (!requireNamespace("jsonlite", quietly = TRUE)) {
        cat('{"error": "jsonlite package not installed"}\n')
        quit(save = "no", status = 1)
    }
    library(lintr)
    library(jsonlite)
})

# Signal that the worker is ready
cat('{"ready": true}\n')
flush(stdout())

while (TRUE) {
    input <- readLines("stdin", n = 1, warn = FALSE)
    if (length(input) == 0 || input == "") next

    tryCatch({
        req <- fromJSON(input)

        lints <- if (!is.null(req$path) && file.exists(req$path)) {
            lint(req$path, text = req$content)
        } else {
            lint(text = req$content)
        }

        result <- lapply(lints, function(l) {
            line <- max(1L, l$line_number) - 1L
            col <- max(1L, l$column_number) - 1L
            end_col <- l$column_number
            if (length(l$ranges)) {
                end_col <- l$ranges[[1]][2]
            }
            list(
                lnum = line,
                col = col,
                end_lnum = line,
                end_col = end_col,
                message = l$message,
                severity = l$type,
                code = l$linter
            )
        })

        response <- toJSON(list(id = req$id, diagnostics = result), auto_unbox = TRUE)
        cat(response, "\n", sep = "")
        flush(stdout())
    }, error = function(e) {
        req_id <- tryCatch(fromJSON(input)$id, error = function(x) 0)
        response <- toJSON(list(id = req_id, error = conditionMessage(e)), auto_unbox = TRUE)
        cat(response, "\n", sep = "")
        flush(stdout())
    })
}
]==]

--- Check if the worker is running
---@return boolean
local function worker_is_running()
    if not worker then return false end
    return vim.fn.jobwait({ worker }, 0)[1] == -1
end

--- Start the lintr worker as a persistent R subprocess
local function start_worker()
    if worker_is_running() then return true end

    local cfg = config()
    local r_cmd = cfg.R_cmd or "R"

    worker = vim.fn.jobstart(
        { r_cmd, "--vanilla", "--quiet", "--slave", "-e", worker_r_code },
        {
            on_stdout = function(_, data)
                for _, line in ipairs(data) do
                    if line ~= "" then
                        vim.schedule(function() M.handle_response(line) end)
                    end
                end
            end,
            on_stderr = function(_, data)
                local msg = table.concat(data, "\n")
                if msg ~= "" and not msg:match("^%s*$") then
                    vim.schedule(function() warn("lintr worker stderr: " .. msg) end)
                end
            end,
            on_exit = function(_, code)
                worker = nil
                if code ~= 0 then
                    vim.schedule(
                        function() warn("lintr worker exited with code " .. code) end
                    )
                end
            end,
            stdin = "pipe",
        }
    )

    if worker == 0 or worker == -1 then
        warn("Failed to start lintr worker")
        worker = nil
        return false
    end

    return true
end

local function stop_worker()
    if worker then
        vim.fn.jobstop(worker)
        worker = nil
    end
end

-----------------------------------------------------------
-- Request/Response Handling
-----------------------------------------------------------

--- Handle response from the lintr worker
---@param json_str string JSON response from worker
function M.handle_response(json_str)
    local ok, resp = pcall(vim.fn.json_decode, json_str)
    if not ok then
        warn("Failed to parse lintr response: " .. json_str)
        return
    end

    -- Handle ready signal
    if resp.ready then return end

    if not resp.id then return end

    local req = pending[resp.id]
    pending[resp.id] = nil

    if not req then return end

    local bufnr = req.bufnr

    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

    if resp.error then
        warn("lintr error: " .. resp.error)
        return
    end

    local diagnostics = {}
    for _, d in ipairs(resp.diagnostics or {}) do
        -- Apply line offset for Rmd/Quarto chunks
        local lnum = d.lnum + (req.line_offset or 0)
        local end_lnum = d.end_lnum + (req.line_offset or 0)

        table.insert(diagnostics, {
            lnum = lnum,
            col = d.col,
            end_lnum = end_lnum,
            end_col = d.end_col,
            message = d.message,
            severity = severity_map[d.severity] or vim.diagnostic.severity.HINT,
            source = "lintr",
            code = d.code,
        })
    end

    -- Merge with existing diagnostics if this is a chunk (not full file)
    if req.is_chunk then
        local existing = vim.diagnostic.get(bufnr, { namespace = ns })
        -- Remove diagnostics from this chunk's line range
        local chunk_start = req.line_offset or 0
        local chunk_end = chunk_start + (req.line_count or 0)
        local filtered = {}
        for _, diag in ipairs(existing) do
            if diag.lnum < chunk_start or diag.lnum >= chunk_end then
                table.insert(filtered, diag)
            end
        end
        -- Add new diagnostics
        for _, diag in ipairs(diagnostics) do
            table.insert(filtered, diag)
        end
        diagnostics = filtered
    end

    vim.diagnostic.set(ns, bufnr, diagnostics)
end

--- Request diagnostics for a buffer
---@param bufnr number Buffer number
function M.request_diagnostics(bufnr)
    if not start_worker() then return end

    local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })

    -- For R files, lint the entire file
    if ft == "r" then
        M.request_file_diagnostics(bufnr)
        return
    end

    -- For Rmd/Quarto, lint each R chunk separately
    if ft == "rmd" or ft == "quarto" then
        M.request_chunk_diagnostics(bufnr)
        return
    end
end

--- Request diagnostics for an entire R file
---@param bufnr number Buffer number
function M.request_file_diagnostics(bufnr)
    if not worker_is_running() then return end

    request_id = request_id + 1
    local path = vim.api.nvim_buf_get_name(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")

    pending[request_id] = {
        bufnr = bufnr,
        is_chunk = false,
    }

    local req = vim.fn.json_encode({
        id = request_id,
        path = path,
        content = content,
    })

    vim.fn.chansend(worker, req .. "\n")
end

--- Request diagnostics for R chunks in Rmd/Quarto files
---@param bufnr number Buffer number
function M.request_chunk_diagnostics(bufnr)
    if not worker_is_running() then return end

    -- Clear existing diagnostics first
    vim.diagnostic.set(ns, bufnr, {})

    local ok, quarto = pcall(require, "r.quarto")
    if not ok then return end

    local chunks = quarto.get_code_chunks(bufnr)
    if not chunks then return end

    -- Get the file path so lintr can find .lintr config
    local file_path = vim.api.nvim_buf_get_name(bufnr)

    for _, chunk in ipairs(chunks) do
        -- Only lint R chunks
        local lang = chunk:get_lang()
        if lang == "r" then
            request_id = request_id + 1

            -- Get chunk range
            local start_row, end_row = chunk:get_range()
            -- start_row points to the ```{r ...} line (1-indexed)
            -- end_row points to the ``` line
            local content_start = start_row
            local content_end = end_row - 1

            if content_end >= content_start then
                local lines =
                    vim.api.nvim_buf_get_lines(bufnr, content_start, content_end, false)
                local content = table.concat(lines, "\n")

                pending[request_id] = {
                    bufnr = bufnr,
                    is_chunk = true,
                    line_offset = content_start,
                    line_count = #lines,
                }

                local req = vim.fn.json_encode({
                    id = request_id,
                    path = file_path,
                    content = content,
                })

                vim.fn.chansend(worker, req .. "\n")
            end
        end
    end
end

-----------------------------------------------------------
-- Debounced Trigger
-----------------------------------------------------------

--- Schedule diagnostics with debouncing
---@param bufnr number Buffer number
---@param delay_ms number Delay in milliseconds
function M.schedule_diagnostics(bufnr, delay_ms)
    -- Cancel existing timer for this buffer
    if debounce_timers[bufnr] then
        vim.fn.timer_stop(debounce_timers[bufnr])
        debounce_timers[bufnr] = nil
    end

    debounce_timers[bufnr] = vim.fn.timer_start(delay_ms, function()
        debounce_timers[bufnr] = nil
        vim.schedule(function()
            if vim.api.nvim_buf_is_valid(bufnr) then M.request_diagnostics(bufnr) end
        end)
    end)
end

-----------------------------------------------------------
-- Language Server Integration Check
-----------------------------------------------------------

--- Check if the R languageserver is attached to the buffer
---@param bufnr number Buffer number
---@return boolean
local function languageserver_attached(bufnr)
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    for _, client in ipairs(clients) do
        if client.name == "r_languageserver" or client.name == "rlanguageserver" then
            return true
        end
    end
    return false
end

-----------------------------------------------------------
-- Public API
-----------------------------------------------------------

--- Setup diagnostics for a buffer
---@param bufnr number Buffer number
function M.setup_buffer(bufnr)
    local cfg = config()
    local diag_cfg = cfg.lsp_diagnostics or {}

    if diag_cfg.enable == false then return end

    -- Skip if languageserver is attached (it provides its own lintr diagnostics)
    if languageserver_attached(bufnr) then return end

    local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if ft ~= "r" and ft ~= "rmd" and ft ~= "quarto" then return end

    local group =
        vim.api.nvim_create_augroup("RNvimDiagnostics" .. bufnr, { clear = true })
    local debounce_ms = diag_cfg.debounce_ms or 500

    -- On save
    if diag_cfg.on_save ~= false then
        vim.api.nvim_create_autocmd("BufWritePost", {
            group = group,
            buffer = bufnr,
            callback = function()
                if not languageserver_attached(bufnr) then
                    M.request_diagnostics(bufnr)
                end
            end,
        })
    end

    -- On text change
    if diag_cfg.on_change ~= false then
        vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
            group = group,
            buffer = bufnr,
            callback = function()
                if not languageserver_attached(bufnr) then
                    M.schedule_diagnostics(bufnr, debounce_ms)
                end
            end,
        })
    end

    -- Initial diagnostics
    M.schedule_diagnostics(bufnr, 100)
end

--- Global setup for diagnostics module
function M.setup()
    local cfg = config()
    local diag_cfg = cfg.lsp_diagnostics or {}

    if diag_cfg.enable == false then return end

    -- Cleanup on Neovim exit
    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = stop_worker,
    })

    -- Also check for languageserver attachment changes
    vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
            local client = vim.lsp.get_client_by_id(args.data.client_id)
            if
                client
                and (
                    client.name == "r_languageserver"
                    or client.name == "rlanguageserver"
                )
            then
                -- Clear our diagnostics when languageserver attaches
                vim.diagnostic.reset(ns, args.buf)
            end
        end,
    })
end

--- Clear diagnostics for a buffer
---@param bufnr number|nil Buffer number (nil for current buffer)
function M.clear(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    vim.diagnostic.reset(ns, bufnr)
end

--- Manually trigger diagnostics for current buffer
function M.run()
    local bufnr = vim.api.nvim_get_current_buf()
    M.request_diagnostics(bufnr)
end

--- Check if diagnostics are enabled
---@return boolean
function M.is_enabled()
    local cfg = config()
    local diag_cfg = cfg.lsp_diagnostics or {}
    return diag_cfg.enable ~= false
end

--- Get the diagnostic namespace
---@return number
function M.get_namespace() return ns end

return M
