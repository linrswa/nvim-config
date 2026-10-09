-- nvim --headless -u NONE -i NONE -l tests/hdl_refresh.lua
-- Real scoped scans and Verilator; fixtures and all writes stay in a temp project.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local uv = vim.uv
local cwd = vim.fn.getcwd()
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/src', 'p'); vim.fn.mkdir(root .. '/tb', 'p')
root = assert(uv.fs_realpath(root))
vim.cmd.cd(vim.fn.fnameescape(root))
local function write(path, lines) vim.fn.writefile(lines, root .. '/' .. path) end
write('.rtl-sources', { 'src/' })
write('src/dut.sv', { 'module dut(output logic y); assign y = 0; endmodule' })
write('src/obsolete.sv', { 'module obsolete; endmodule' })
local errors, warnings = {}, {}
local real_notify, real_system = vim.notify, vim.system
vim.notify = function(message, level)
    local target = level == vim.log.levels.ERROR and errors or warnings
    target[#target + 1] = tostring(message)
end
local sources = require('hdl.sources')
local real_scan = sources.scan
local scans, starts, completed = 0, 0, 0
local hold_scan, hold_result, after_scan, on_start = false, false, nil, nil
local scan_callbacks, result_callbacks, snapshot_dirs, launched_lists = {}, {}, {}, {}
sources.scan = function(project, silent, callback)
    scans = scans + 1
    real_scan(project, silent, function(err, changed)
        if after_scan then local action = after_scan; after_scan = nil; action() end
        local deliver = function() callback(err, changed) end
        if hold_scan then scan_callbacks[#scan_callbacks + 1] = deliver else deliver() end
    end)
end
vim.system = function(cmd, opts, callback)
    assert(cmd[1] == 'verilator', 'unexpected process')
    starts = starts + 1
    local list = vim.fn.readfile(opts.cwd .. '/.verilator-live.f')
    local relative = {}
    for _, entry in ipairs(list) do
        local path = entry:sub(2, -2)
        assert(uv.fs_stat(path), 'launched with nonexistent input: ' .. path)
        relative[#relative + 1] = path:sub(#opts.cwd + 2)
    end
    launched_lists[#launched_lists + 1] = relative
    snapshot_dirs[#snapshot_dirs + 1] = opts.cwd
    if on_start then on_start(opts.cwd, relative) end
    local delayed = hold_result
    return real_system(cmd, opts, function(result)
        local deliver = function()
            callback(result)
            vim.schedule(function() completed = completed + 1 end)
        end
        if delayed then result_callbacks[#result_callbacks + 1] = deliver else deliver() end
    end)
end
require('lsp.hdl')
vim.lsp.enable('verible', false)
local lint = require('lsp.verilator_lint')
local ns = vim.api.nvim_get_namespaces()['verilator-lint']
local function wait(check, message)
    assert(vim.wait(10000, check, 10), message .. '\n' .. vim.inspect(errors))
end
local function finish(target)
    wait(function() return completed >= target or #errors > 0 end, 'lint did not complete')
    assert(#errors == 0, vim.inspect(errors))
    assert(completed >= target)
end
local function event(name, buf)
    vim.api.nvim_exec_autocmds(name, buf and { buffer = buf } or {})
end
local function filelist() return vim.fn.readfile(root .. '/verible.filelist') end
local function contains(list, path) return vim.tbl_contains(list, path) end
local source, obsolete
local ok, err = xpcall(function()
    assert(vim.fn.executable('verilator') == 1, 'Verilator required')
    obsolete = vim.fn.bufadd(root .. '/src/obsolete.sv'); vim.fn.bufload(obsolete)
    source = vim.fn.bufadd(root .. '/src/dut.sv'); vim.fn.bufload(source)
    vim.api.nvim_set_current_buf(source)
    vim.b[source].verilator_top_module = 'dut'
    vim.b[source].verilator_lint_args = { '--Wno-fatal' }
    for _ = 1, 4 do event('BufEnter', source); event('FocusGained'); event('TermLeave') end
    finish(1)
    assert(scans == 1 and starts == 1, 'event burst did not coalesce')
    assert(contains(filelist(), 'src/obsolete.sv'), 'initial discovery failed')
    local listbuf = vim.fn.bufadd(root .. '/verible.filelist'); vim.fn.bufload(listbuf)
    assert(contains(vim.api.nvim_buf_get_lines(listbuf, 0, -1, false), 'src/obsolete.sv'))

    -- A moved file is removed from scope and cannot be resurrected by a loaded buffer.
    vim.api.nvim_buf_set_lines(obsolete, 0, -1, false, { 'module obsolete; wire unsaved_note; endmodule' })
    assert(uv.fs_rename(root .. '/src/obsolete.sv', root .. '/tb/obsolete.sv'))
    on_start = function(dir, list)
        assert(not contains(list, 'src/obsolete.sv') and not contains(list, 'tb/obsolete.sv'))
        assert(not uv.fs_stat(dir .. '/src/obsolete.sv'), 'deleted buffer resurrected in snapshot')
    end
    event('FocusGained'); finish(2); on_start = nil
    local count, scan_count = starts, scans
    vim.api.nvim_set_current_buf(obsolete)
    wait(function() return scans > scan_count end, 'old buffer did not refresh')
    vim.wait(500)
    assert(starts == count, 'lint ran on a moved buffer')
    assert(table.concat(warnings, '\n'):find('file moved/deleted', 1, true), 'missing moved-buffer warning')
    assert(vim.api.nvim_buf_get_lines(obsolete, 0, -1, false)[1]:find('unsaved_note', 1, true), 'discarded buffer edits')
    vim.api.nvim_set_current_buf(source); finish(3)

    write('src/added.sv', { 'module added; endmodule' })
    event('TermLeave'); finish(4)
    assert(contains(filelist(), 'src/added.sv'), 'new file not discovered')
    -- A missed external event is recovered by one scan on the next lint request.
    assert(uv.fs_unlink(root .. '/src/added.sv'))
    scan_count = scans
    event('TextChanged', source); finish(5)
    assert(scans == scan_count + 1 and not contains(filelist(), 'src/added.sv'), 'missing-input recovery failed')
    scan_count = scans
    event('TextChanged', source); finish(6)
    assert(scans == scan_count, 'ordinary typing rescanned unchanged scope')

    -- Truly new unsaved sources remain usable; saving then deleting changes their status.
    local fresh = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(fresh, root .. '/src/fresh.sv')
    vim.api.nvim_buf_set_lines(fresh, 0, -1, false, { 'module fresh; initial $finish; endmodule' })
    vim.b[fresh].verilator_top_module = 'fresh'
    vim.b[fresh].verilator_lint_args = { '--Wno-fatal' }
    vim.api.nvim_set_current_buf(fresh); finish(7)
    assert(contains(launched_lists[#launched_lists], 'src/fresh.sv'), 'unsaved source not linted')
    assert(not uv.fs_stat(root .. '/src/fresh.sv') and not contains(filelist(), 'src/fresh.sv'))
    vim.cmd.write(); finish(8)
    assert(contains(filelist(), 'src/fresh.sv'), 'save did not refresh scope')
    assert(uv.fs_unlink(root .. '/src/fresh.sv'))
    vim.api.nvim_set_current_buf(source); finish(9)
    assert(not contains(filelist(), 'src/fresh.sv'))

    -- Typing during a pending refresh must still wait for a current scan result.
    hold_scan = true; count = starts
    event('FocusGained')
    wait(function() return #scan_callbacks == 1 end, 'scan callback not held')
    assert(starts == count, 'lint started before scan callback')
    hold_scan = false
    event('TextChanged', source); finish(10)
    scan_callbacks[1](); scan_callbacks = {}; vim.wait(100)
    assert(starts == count + 1, 'superseded scan launched stale lint')

    -- Scan failure preserves the list but must not lint it, including on subsequent typing.
    local preserved = filelist()
    write('.rtl-sources', { 'src/missing.sv' }); count = starts
    event('FocusGained')
    wait(function() return #errors > 0 end, 'invalid scope did not fail')
    assert(starts == count and vim.deep_equal(filelist(), preserved), 'failed refresh launched lint/overwrote list')
    errors = {}; event('TextChanged', source)
    wait(function() return #errors > 0 end, 'typing bypassed failed refresh')
    assert(starts == count)
    errors = {}; write('.rtl-sources', { 'src/' })
    event('FocusGained'); finish(11)

    -- A file removed immediately after a scan cannot cause an infinite recovery loop.
    write('src/race.sv', { 'module race; endmodule' })
    after_scan = function() assert(uv.fs_unlink(root .. '/src/race.sv')) end
    scan_count, count = scans, starts
    event('FocusGained')
    wait(function() return #errors > 0 end, 'post-scan deletion was not detected')
    vim.wait(400)
    assert(scans == scan_count + 1 and starts == count, 'unbounded retry or missing input launched')
    errors = {}; event('FocusGained'); finish(12)

    -- A completed but delayed old process cannot publish diagnostics after a newer refresh.
    hold_result = true
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { 'module dut(output logic y); assign y = missing_signal; endmodule' })
    event('TextChanged', source)
    wait(function() return #result_callbacks == 1 end, 'old process result not held')
    hold_result = false
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { 'module dut(output logic y); assign y = 0; endmodule' })
    event('FocusGained'); finish(13)
    result_callbacks[1](); result_callbacks = {}
    wait(function() return completed == 14 end, 'old process callback not delivered')
    for _, diagnostic in ipairs(vim.diagnostic.get(source, { namespace = ns })) do
        assert(not diagnostic.message:find('missing_signal', 1, true), 'stale diagnostic published')
    end
    assert(#errors == 0, vim.inspect(errors))

    -- Current-source overlays must precede validation, even for explicit excluded paths.
    for _, dir in ipairs({ 'build', 'obj_dir' }) do
        vim.fn.mkdir(root .. '/' .. dir, 'p')
        write(dir .. '/top.sv', { 'module top; initial $finish; endmodule' })
        write('.rtl-sources', { dir .. '/top.sv' })
        local target = completed + 1
        local special = vim.fn.bufadd(root .. '/' .. dir .. '/top.sv'); vim.fn.bufload(special)
        vim.b[special].verilator_top_module = 'top'
        vim.b[special].verilator_lint_args = { '--Wno-fatal' }
        vim.api.nvim_set_current_buf(special); finish(target)
        assert(contains(launched_lists[#launched_lists], dir .. '/top.sv'), 'scoped excluded source not overlaid')
        vim.api.nvim_buf_delete(special, { force = true })
    end
    write('.rtl-sources', { 'src/' })
    local target = completed + 1
    vim.api.nvim_set_current_buf(source); event('BufEnter', source); finish(target)

    -- Rename across projects without changing the text tick: old diagnostics/work
    -- must be invalidated, including results already completed but not delivered.
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { 'module dut(output logic y); assign y = rename_missing; endmodule' })
    target = completed + 1; event('TextChanged', source); finish(target)
    assert(#vim.diagnostic.get(source, { namespace = ns }) > 0, 'rename fixture needs published diagnostics')
    -- Wiping a hidden generated-list buffer must not erase diagnostics or cancel
    -- unrelated pending lint while the HDL target remains current.
    local before_wipe = vim.diagnostic.get(source, { namespace = ns })
    vim.api.nvim_buf_delete(listbuf, { force = true })
    assert(vim.deep_equal(vim.diagnostic.get(source, { namespace = ns }), before_wipe), 'filelist wipe cleared diagnostics')
    listbuf = vim.fn.bufadd(root .. '/verible.filelist'); vim.fn.bufload(listbuf)
    target = completed + 1; event('TextChanged', source)
    vim.api.nvim_buf_delete(listbuf, { force = true }); finish(target)
    hold_result = true; event('TextChanged', source)
    wait(function() return #result_callbacks == 1 end, 'rename result not held')
    local old_name = vim.api.nvim_buf_get_name(source)
    local old_tick = vim.api.nvim_buf_get_changedtick(source)
    vim.fn.mkdir(root .. '/other/src', 'p')
    write('other/.rtl-sources', { 'src/' })
    assert(uv.fs_rename(old_name, root .. '/other/src/dut.sv'))
    hold_result = false
    vim.api.nvim_buf_set_name(source, root .. '/other/src/dut.sv')
    assert(vim.api.nvim_buf_get_changedtick(source) == old_tick, 'rename unexpectedly changed text tick')
    assert(#vim.diagnostic.get(source, { namespace = ns }) == 0, 'rename did not clear old diagnostics')
    local prior_old_buf = vim.fn.bufnr(old_name)
    target = completed + 2 -- one stale delivery and one new-project lint
    result_callbacks[1](); result_callbacks = {}
    finish(target)
    assert(vim.fn.bufnr(old_name) == prior_old_buf, 'stale result recreated old buffer')
    if prior_old_buf ~= -1 then
        assert(#vim.diagnostic.get(prior_old_buf, { namespace = ns }) == 0, 'stale result published on alternate buffer')
    end

    -- Renaming out of HDL patterns must also cancel the former project's work.
    hold_result = true; event('TextChanged', source)
    wait(function() return #result_callbacks == 1 end, 'non-HDL rename result not held')
    old_name = vim.api.nvim_buf_get_name(source)
    assert(uv.fs_rename(old_name, root .. '/other/notes.txt'))
    count = starts; hold_result = false
    vim.api.nvim_buf_set_name(source, root .. '/other/notes.txt')
    prior_old_buf = vim.fn.bufnr(old_name)
    target = completed + 1
    result_callbacks[1](); result_callbacks = {}; finish(target)
    vim.wait(600)
    assert(starts == count and vim.fn.bufnr(old_name) == prior_old_buf, 'non-HDL rename did not cancel old lint')
    if prior_old_buf ~= -1 then
        assert(#vim.diagnostic.get(prior_old_buf, { namespace = ns }) == 0, 'stale non-HDL rename diagnostics')
    end
    assert(#vim.diagnostic.get(source, { namespace = ns }) == 0, 'non-HDL rename retained old diagnostics')
    for _, dir in ipairs(snapshot_dirs) do assert(not uv.fs_stat(dir), 'snapshot leaked') end
end, debug.traceback)
-- Release any held callbacks so temporary snapshots can be cleaned even on failure.
hold_scan, hold_result = false, false
for _, callback in ipairs(scan_callbacks) do callback() end
for _, callback in ipairs(result_callbacks) do callback() end
vim.wait(100)
vim.notify, vim.system, sources.scan = real_notify, real_system, real_scan
vim.cmd.cd(vim.fn.fnameescape(cwd))
vim.fn.delete(root, 'rf')
if not ok then error(err) end
print('RTL event refresh: coalescing, move/add/delete, old/new buffers, bounded recovery, scan/process races: PASS')
vim.cmd('qa!')
