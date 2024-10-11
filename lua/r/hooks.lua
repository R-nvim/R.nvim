local M = {}

function M.run_after_config(config)
    if config.hook and config.hook.after_config then
        vim.schedule(function() config.hook.after_config() end)
    end
end

function M.run_on_filetype(config)
    if config.hook and config.hook.on_filetype then
        vim.schedule(function() config.hook.on_filetype() end)
    end
end

function M.run_after_R_start(config)
    if config.hook and config.hook.after_R_start then
        vim.schedule(function() config.hook.after_R_start() end)
    end
end

function M.run_after_ob_open(config)
    if config.hook and config.hook.after_ob_open then
        vim.schedule(function() config.hook.after_ob_open() end)
    end
end

return M
