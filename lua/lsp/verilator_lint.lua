local M = {}
local ns = vim.api.nvim_create_namespace("verilator-lint")
vim.diagnostic.config({ update_in_insert = true }, ns)
local projects = {}
local snapshots = {}
local uv = vim.uv
local excluded = { [".git"] = true, build = true, obj_dir = true }

local function inside(path, root)
    return path:sub(1, #root + 1) == root .. "/"
end

local function cleanup(run)
    if run and run.dir then
        vim.fn.delete(run.dir, "rf")
        snapshots[run] = nil
        run.dir = nil
    end
end

local function clear(state)
    for buf in pairs(state.buffers) do
        if vim.api.nvim_buf_is_valid(buf) then
            vim.diagnostic.reset(ns, buf)
        end
    end
    state.buffers = {}
end

-- Mirror directories, but link unchanged files rather than copying large traces.
-- Never write through these links: buffer overlays explicitly unlink them first.
-- Directory symlinks are not followed (external trees/cycles are not snapshots).
local function mirror(source, target)
    assert(uv.fs_mkdir(target, 448))
    local entries = assert(uv.fs_scandir(source))
    while true do
        local name, kind = uv.fs_scandir_next(entries)
        if not name then break end
        if not excluded[name] then
            local from, to = source .. "/" .. name, target .. "/" .. name
            if kind == "directory" then
                mirror(from, to)
            elseif kind == "file" then
                assert(uv.fs_symlink(from, to))
            elseif kind == "link" then
                local stat = uv.fs_stat(from)
                if stat and stat.type == "file" then
                    assert(uv.fs_symlink(from, to))
                end
            end
        end
    end
end

local function snapshot(root, run, source_buf)
    run.dir = vim.fn.tempname()
    snapshots[run] = true
    mirror(root, run.dir)
    run.dir = assert(uv.fs_realpath(run.dir))
    run.ticks = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local path = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
        -- macOS temp roots may be spelled /var or /private/var. Resolve the
        -- parent too, so a new (not yet saved) file can still be overlaid.
        local parent = uv.fs_realpath(vim.fs.dirname(path))
        if parent then path = parent .. "/" .. vim.fs.basename(path) end
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" and inside(path, root) then
            local relative = path:sub(#root + 2)
            local skip = false
            for part in relative:gmatch("[^/]+") do
                if excluded[part] then skip = true end
            end
            if not skip then
                local dest = run.dir .. "/" .. relative
                vim.fn.mkdir(vim.fs.dirname(dest), "p")
                if uv.fs_lstat(dest) then assert(uv.fs_unlink(dest)) end
                local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                if vim.bo[buf].endofline then lines[#lines + 1] = "" end
                assert(vim.fn.writefile(lines, dest, "b") == 0)
                run.ticks[buf] = vim.api.nvim_buf_get_changedtick(buf)
            end
        end
    end
    -- VeribleScan produces a plain source list, not a Verilator command file.
    -- Reject flags/nested lists rather than silently reading unsaved files from
    -- the real tree. Absolute project-local entries are remapped as well.
    local list, listed = {}, {}
    for _, line in ipairs(vim.fn.readfile(run.dir .. "/verible.filelist")) do
        local path = vim.trim(line)
        if path ~= "" and not path:match("^#") and not path:match("^//") then
            assert(not path:match("^[-+]"), "verible.filelist must contain source paths only (run :VeribleScan)")
            if path:sub(1, 1) ~= "/" then path = root .. "/" .. path end
            path = vim.fs.normalize(path)
            assert(inside(path, root), "external filelist sources are not supported by live lint: " .. path)
            list[#list + 1] = '"' .. run.dir .. "/" .. path:sub(#root + 2) .. '"'
            listed[path] = true
        end
    end
    -- A testbench may intentionally be outside the RTL source scope. Lint it
    -- alongside that scope, using its overlaid (possibly unsaved) snapshot.
    local current = vim.fs.normalize(vim.api.nvim_buf_get_name(source_buf))
    local parent = uv.fs_realpath(vim.fs.dirname(current))
    if parent then current = parent .. '/' .. vim.fs.basename(current) end
    if inside(current, root) and (current:match('%.sv$') or current:match('%.v$')) then
        local dest = run.dir .. '/' .. current:sub(#root + 2)
        -- Explicitly overlay the current source even in build/obj_dir, which
        -- are normally omitted from the mirror. Never write through a link.
        vim.fn.mkdir(vim.fs.dirname(dest), 'p')
        if uv.fs_lstat(dest) then assert(uv.fs_unlink(dest)) end
        local content = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
        if vim.bo[source_buf].endofline then content[#content + 1] = '' end
        assert(vim.fn.writefile(content, dest, 'b') == 0)
        run.ticks[source_buf] = vim.api.nvim_buf_get_changedtick(source_buf)
        if not listed[current] then list[#list + 1] = '"' .. dest .. '"' end
    end
    run.filelist = run.dir .. "/.verilator-live.f"
    if uv.fs_lstat(run.filelist) then assert(uv.fs_unlink(run.filelist)) end
    assert(vim.fn.writefile(list, run.filelist) == 0)
end

-- Verilator diagnostics use one-based locations; Neovim uses zero-based ones.
local function parse(output, root, original)
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
                if inside(path, root) then path = original .. path:sub(#root + 1) end
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
    root = vim.fs.normalize(uv.fs_realpath(root) or root)
    local state = projects[root] or { generation = 0, buffers = {} }
    projects[root] = state
    state.generation = state.generation + 1
    local generation = state.generation
    clear(state) -- Do not leave diagnostics from old text visible during debounce.
    if state.run and state.run.process then
        state.run.process:kill(9)
        -- Its completion callback removes the snapshot after the child exits.
    end
    state.run = nil

    vim.defer_fn(function()
        if state.generation ~= generation or not vim.api.nvim_buf_is_valid(source_buf) then return end
        if vim.fn.executable("verilator") ~= 1 then
            vim.notify("找不到 verilator，請檢查 Neovim 的 PATH", vim.log.levels.ERROR)
            return
        end
        local run = {}
        local ok, err = pcall(snapshot, root, run, source_buf)
        if not ok then
            cleanup(run)
            vim.notify("無法建立 Verilator snapshot：" .. tostring(err), vim.log.levels.ERROR)
            return
        end
        local cmd = {
            "verilator", "--lint-only", "--Wall", "--timing",
            "--timescale", "1ns/1ps", "-f", run.filelist,
        }
        local top = vim.b[source_buf].verilator_top_module or vim.g.verilator_top_module
        if top and top ~= "" then vim.list_extend(cmd, { "--top-module", top }) end
        -- Extra flags must be lint-only options with project-relative paths.
        -- Relative -I and --relative-includes retain Verilator's usual semantics
        -- in the mirrored tree. Absolute `include/-I paths, external sources,
        -- nested command files and directory symlinks are NOT buffer overlays.
        local extra = vim.b[source_buf].verilator_lint_args or vim.g.verilator_lint_args or {}
        vim.list_extend(cmd, extra)
        state.run = run
        local started, process = pcall(vim.system, cmd, { cwd = run.dir, text = true }, function(result)
            vim.schedule(function()
                local dir = run.dir
                cleanup(run)
                if state.generation ~= generation or not dir then return end
                state.run = nil
                for buf, tick in pairs(run.ticks) do
                    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf)
                        or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
                        return -- Also protects edits before TextChanged is delivered.
                    end
                end
                local output = (result.stderr or "") .. "\n" .. (result.stdout or "")
                local by_file = parse(output, dir, root)
                for path, diagnostics in pairs(by_file) do
                    local buf = vim.fn.bufadd(path)
                    vim.diagnostic.set(ns, buf, diagnostics)
                    state.buffers[buf] = true
                end
                if result.code ~= 0 and next(by_file) == nil then
                    vim.notify("Verilator lint 失敗：\n" .. vim.trim(output), vim.log.levels.ERROR)
                end
            end)
        end)
        if started then
            run.process = process
        else
            state.run = nil
            cleanup(run)
            vim.notify("無法啟動 Verilator：" .. tostring(process), vim.log.levels.ERROR)
        end
    end, 300)
end

vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("VerilatorSnapshotCleanup", { clear = true }),
    callback = function()
        for _, state in pairs(projects) do state.generation = state.generation + 1 end
        for run in pairs(snapshots) do
            if run.process then
                run.process:kill(9)
                pcall(function() run.process:wait(1000) end)
            end
            cleanup(run)
        end
    end,
})

return M
