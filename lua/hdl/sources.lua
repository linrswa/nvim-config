-- Explicit source scopes only. Work is chunked; superseded scans cannot publish.
local M = {}
local uv = vim.uv
local jobs = {}
function M.root(buf) return vim.fs.root(buf or 0, { '.rtl-sources', '.git', 'CMakeLists.txt' }) end
function M.parse(lines)
    local includes, excludes = {}, {}
    for n, line in ipairs(lines) do
        line = vim.trim(line)
        if line ~= '' and not line:match('^#') and not line:match('^//') then
            local exclude = line:sub(1, 1) == '!'
            if exclude then line = vim.trim(line:sub(2)) end
            assert(line ~= '' and not line:match('^[/~]') and not line:match('^%a:')
                and not line:find('[*?%[%]$"\\]') and not line:find('[\r\n]'),
                'line ' .. n .. ': expected a relative file/folder, not a glob or expansion')
            for part in line:gmatch('[^/]+') do assert(part ~= '..', 'line ' .. n .. ': parent paths are not allowed') end
            line = vim.fs.normalize(line):gsub('/$', '')
            local target = exclude and excludes or includes
            target[#target + 1] = line
        end
    end
    return includes, excludes
end
function M.scan(root, silent, done)
    if not root then vim.notify('HDL: cannot find project root', vim.log.levels.ERROR); return end
    local job = {}; jobs[root] = job
    local function finish(err, changed)
        if jobs[root] ~= job then return end
        jobs[root] = nil
        if err then vim.notify('HDL scan: ' .. tostring(err), vim.log.levels.ERROR)
        elseif not silent then vim.notify(changed and 'Updated verible.filelist' or 'verible.filelist unchanged') end
        if done then done(err, changed) end
    end
    local original
    local ok, inc, exc = pcall(function()
        original = vim.fn.readfile(root .. '/.rtl-sources')
        return M.parse(original)
    end)
    if not ok then finish(inc); return end
    local queue, seen, files, index, dir = {}, {}, {}, 1, nil
    for _, path in ipairs(inc) do queue[#queue + 1] = path end
    local function excluded(path)
        for _, p in ipairs(exc) do if p == '.' or path == p or path:sub(1, #p + 1) == p .. '/' then return true end end
        return false
    end
    local function inspect(path)
        if seen[path] or excluded(path) then return end
        seen[path] = true
        -- Explicit scopes through directory links must not bypass the traversal rule.
        local prefix = root
        for part in path:gmatch('[^/]+') do
            prefix = prefix .. '/' .. part
            local st = assert(uv.fs_lstat(prefix))
            if st.type == 'link' then return end
        end
        local st = assert(uv.fs_lstat(root .. '/' .. path))
        if st.type == 'directory' then
            dir = { handle = assert(uv.fs_scandir(root .. '/' .. path)), path = path }
        elseif st.type == 'file' and (path:match('%.sv$') or path:match('%.v$')) then
            assert(not path:match('^[-+#]') and not path:find('[$"\r\n\\]'),
                'source path cannot be represented safely in a plain filelist: ' .. path)
            files[#files + 1] = path
        end
    end
    local function step()
        if jobs[root] ~= job then return end
        local success, err = pcall(function()
            for _ = 1, 100 do
                if dir then
                    local name = uv.fs_scandir_next(dir.handle)
                    if name then queue[#queue + 1] = (dir.path == '.' and '' or dir.path .. '/') .. name
                    else dir = nil end
                elseif queue[index] then
                    local path = queue[index]; index = index + 1; inspect(path)
                else
                    assert(vim.deep_equal(original, vim.fn.readfile(root .. '/.rtl-sources')),
                        '.rtl-sources changed during scan; run :VeribleScan again')
                    table.sort(files)
                    local output = root .. '/verible.filelist'
                    local readable, old = pcall(vim.fn.readfile, output)
                    if readable and vim.deep_equal(old, files) then finish(nil, false); return end
                    local temp = output .. '.tmp.' .. uv.os_getpid() .. '.' .. uv.hrtime()
                    local written, failure = pcall(function()
                        assert(vim.fn.writefile(files, temp) == 0)
                        assert(uv.fs_rename(temp, output))
                    end)
                    if not written then uv.fs_unlink(temp); error(failure) end
                    finish(nil, true); return
                end
            end
            vim.schedule(step)
        end)
        if not success then finish(err) end
    end
    vim.schedule(step)
end
function M.open()
    local root = M.root()
    if not root then vim.notify('HDL: cannot find project root', vim.log.levels.ERROR); return end
    local path = root .. '/.rtl-sources'
    local buf = vim.fn.bufadd(path); vim.fn.bufload(buf)
    vim.bo[buf].bufhidden = 'hide'
    if not uv.fs_stat(path) and vim.api.nvim_buf_line_count(buf) == 1 then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            '# Relative RTL files/folders, one per line; no globs.',
            '# !path excludes a file/folder. Directory symlinks are not followed.',
            '# Example: rtl   (put on its own line)',
        })
    end
    local w, h = math.max(1, math.min(90, vim.o.columns - 4)), math.max(1, math.min(24, vim.o.lines - 4))
    vim.api.nvim_open_win(buf, true, { relative = 'editor', width = w, height = h,
        row = math.floor((vim.o.lines - h) / 2), col = math.floor((vim.o.columns - w) / 2),
        border = 'rounded', title = ' .rtl-sources — :w scans, :q closes ', style = 'minimal' })
end
return M
