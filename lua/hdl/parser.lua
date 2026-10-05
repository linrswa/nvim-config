-- One global worker, latest-request queue, saved-source stat cache.
local M = {}
local cache, revisions = {}, {}
local running, pending
local function key(path)
    local s = vim.uv.fs_stat(path)
    if not s then return end
    return table.concat({ s.size, s.mtime.sec, s.mtime.nsec, s.ctime.sec, s.ctime.nsec, revisions[path] or 0 }, ':')
end
local function canonical(path) return vim.uv.fs_realpath(path) or vim.fs.normalize(path) end
function M.invalidate(path)
    path = canonical(path)
    cache[path] = nil; revisions[path] = (revisions[path] or 0) + 1
end
local pump
pump = function()
    if running or not pending then return end
    local request = pending; pending = nil
    if request.cancelled then pump(); return end
    local stamp = key(request.path)
    if stamp and cache[request.path] and cache[request.path].stamp == stamp then
        request.callback(cache[request.path].result); pump(); return
    end
    local ok, lines = pcall(vim.fn.readfile, request.path, 'b')
    if not ok then request.callback({ error = tostring(lines) }); pump(); return end
    local source = table.concat(lines, '\n')
    local binary = 'verible-verilog-syntax'
    if vim.fn.executable(binary) ~= 1 then binary = vim.fn.expand('~/.local/share/nvim/mason/bin/' .. binary) end
    running = request
    local started, process = pcall(vim.system, { binary, '--export_json', '--printtree', '-' },
        { stdin = source, text = true, cwd = request.root, timeout = 15000 }, function(result)
            vim.schedule(function()
                running = nil
                if not request.cancelled then
                    local parsed, value = pcall(function()
                        assert(result.code == 0, 'Verible failed: ' .. (result.stderr or ''):sub(1, 800))
                        local data = vim.json.decode(result.stdout)
                        assert(data['-'] and data['-'].tree, 'Missing Verible tree')
                        local modules, warnings = require('hdl.instance').parse(source, data['-'], request.path)
                        assert(#modules > 0, #warnings > 0 and table.concat(warnings, '\n') or 'No supported modules')
                        return { modules = modules, warnings = warnings }
                    end)
                    value = parsed and value or { error = tostring(value) }
                    if key(request.path) ~= stamp then value = { error = 'Source changed; refocus to retry' }
                    elseif stamp then cache[request.path] = { stamp = stamp, result = value } end
                    request.callback(value)
                end
                pump()
            end)
        end)
    if started then request.process = process
    else running = nil; request.callback({ error = tostring(process) }); pump() end
end
function M.request(path, root, callback)
    local request = { path = canonical(path), root = root, callback = callback }
    if pending then pending.cancelled = true end
    pending = request
    pump()
    return function()
        request.cancelled = true
        if request.process then request.process:kill(9) end
        if pending == request then pending = nil end
    end
end
return M
