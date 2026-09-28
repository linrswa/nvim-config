local M = {}
local ns = vim.api.nvim_create_namespace("verilator-lint")
local projects = {}

-- Verilator diagnostics use one-based locations; Neovim uses zero-based ones.
local function parse(output, root)
    local by_file = {}
    local last
    for line in output:gmatch("[^\r\n]+") do
        local kind, rest = line:match("^%%(Error[^:]*):%s*(.*)$")
        if not kind then
            kind, rest = line:match("^%%(Warning[^:]*):%s*(.*)$")
        end
        if kind then
            last = nil
            local path, row, col, message = rest:match("^(.-):(%d+):(%d+):%s*(.*)$")
            if not path then
                path, row, message = rest:match("^(.-):(%d+):%s*(.*)$")
                col = "1"
            end
            if path then
                if not vim.startswith(path, "/") then
                    path = root .. "/" .. path
                end
                path = vim.fs.normalize(path)
                by_file[path] = by_file[path] or {}
                last = {
                    lnum = math.max(tonumber(row) - 1, 0),
                    col = math.max(tonumber(col) - 1, 0),
                    severity = kind:match("^Error") and vim.diagnostic.severity.ERROR
                        or vim.diagnostic.severity.WARN,
                    message = message,
                    source = "verilator",
                    code = kind:match("^[^-]+%-(.+)$"),
                }
                table.insert(by_file[path], last)
            end
        elseif last and line:match("^%s+:%s*%.%.%.%s*note:") then
            last.message = last.message .. "\n" .. vim.trim(line)
        end
    end
    return by_file
end

function M.run(root, source_buf)
    if vim.fn.executable("verilator") ~= 1 then
        vim.notify("找不到 verilator，請檢查 Neovim 的 PATH", vim.log.levels.ERROR)
        return
    end
    local state = projects[root] or { generation = 0, buffers = {} }
    projects[root] = state
    state.generation = state.generation + 1
    local generation = state.generation
    if state.process then
        state.process:kill(15)
        state.process = nil
    end

    -- Debounce rapid saves and discard results from superseded runs.
    vim.defer_fn(function()
        if state.generation ~= generation or not vim.api.nvim_buf_is_valid(source_buf) then
            return
        end
        local cmd = {
            "verilator", "--lint-only", "--Wall", "--timing",
            "--timescale", "1ns/1ps", "-f", "verible.filelist",
        }
        -- Optional per-buffer/global settings for other projects. With no top
        -- override, Verilator discovers the top automatically.
        local top = vim.b[source_buf].verilator_top_module or vim.g.verilator_top_module
        if top and top ~= "" then
            vim.list_extend(cmd, { "--top-module", top })
        end
        local extra = vim.b[source_buf].verilator_lint_args or vim.g.verilator_lint_args or {}
        vim.list_extend(cmd, extra)
        local ok, process = pcall(vim.system, cmd, { cwd = root, text = true }, function(result)
            vim.schedule(function()
                if state.generation ~= generation then
                    return
                end
                state.process = nil
                local output = (result.stderr or "") .. "\n" .. (result.stdout or "")
                local by_file = parse(output, root)
                for buf in pairs(state.buffers) do
                    if vim.api.nvim_buf_is_valid(buf) then
                        vim.diagnostic.reset(ns, buf)
                    end
                end
                state.buffers = {}
                for path, diagnostics in pairs(by_file) do
                    local buf = vim.fn.bufadd(path)
                    vim.diagnostic.set(ns, buf, diagnostics)
                    state.buffers[buf] = true
                end
                -- Fileless errors (bad flags, missing includes/filelist, etc.)
                -- must not disappear merely because they lack a source location.
                if result.code ~= 0 and next(by_file) == nil then
                    vim.notify("Verilator lint 失敗：\n" .. vim.trim(output), vim.log.levels.ERROR)
                end
            end)
        end)
        if ok then
            state.process = process
        else
            vim.notify("無法啟動 Verilator：" .. tostring(process), vim.log.levels.ERROR)
        end
    end, 150)
end

return M
