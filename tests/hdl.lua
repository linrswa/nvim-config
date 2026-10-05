-- nvim --headless -u NONE -l tests/hdl.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/rtl', 'p'); vim.fn.mkdir(root .. '/tb', 'p'); vim.fn.mkdir(root .. '/.git', 'p')
root = assert(vim.uv.fs_realpath(root))
local function write(path, lines) assert(vim.fn.writefile(lines, root .. '/' .. path) == 0) end
local function wait(test, message) assert(vim.wait(6000, test, 10), message) end
local sources = require('hdl.sources')
local notices = {}; vim.notify = function(s) notices[#notices + 1] = s end
local function scan()
    local done, failure, changed
    sources.scan(root, true, function(err, c) done, failure, changed = true, err, c end)
    wait(function() return done end, 'scan timeout')
    return failure, changed
end
write('rtl/a.sv', { 'module a(input logic a, output logic z); assign z=a; endmodule' })
write('rtl/b.v', { 'module b; endmodule', 'module c; endmodule' })
write('tb/a_tb.sv', { 'module a_tb; endmodule' })
assert(vim.uv.fs_symlink(root, root .. '/rtl/cycle', { dir = true }))
write('.hdl-sources', { '# scope', 'rtl/', 'rtl/a.sv', '!rtl/b.v' })
assert(not scan())
assert(vim.deep_equal(vim.fn.readfile(root .. '/verible.filelist'), { 'rtl/a.sv' }))
local before = vim.uv.fs_stat(root .. '/verible.filelist')
local err, changed = scan(); assert(not err and not changed)
assert(vim.deep_equal(before.mtime, vim.uv.fs_stat(root .. '/verible.filelist').mtime))
write('.hdl-sources', { 'missing' }); assert(scan())
assert(vim.deep_equal(vim.fn.readfile(root .. '/verible.filelist'), { 'rtl/a.sv' }))
vim.fn.delete(root .. '/.hdl-sources'); assert(scan())
for _, line in ipairs({ '../rtl', '/rtl', 'rtl/*.sv', 'rtl/[ab]', '~/rtl' }) do assert(not pcall(sources.parse, { line })) end
write('.hdl-sources', { 'rtl' })
local stale = false
sources.scan(root, true, function() stale = true end)
write('.hdl-sources', { 'rtl/a.sv' }); assert(not scan()); assert(not stale)
write('.hdl-sources', { 'rtl' })
local cross_done, cross_error
sources.scan(root, true, function(e) cross_done, cross_error = true, e end)
write('.hdl-sources', { 'tb' }) -- emulate another editor, without starting a local scan
wait(function() return cross_done end, 'cross-editor scan timeout'); assert(cross_error)
assert(vim.deep_equal(vim.fn.readfile(root .. '/verible.filelist'), { 'rtl/a.sv' }))
write('.hdl-sources', { 'rtl/cycle/rtl' }); assert(not scan())
assert(#vim.fn.readfile(root .. '/verible.filelist') == 0, 'followed directory symlink')
write('.hdl-sources', { 'rtl' }); assert(not scan())

local parser = require('hdl.parser')
local real_system, starts, workers, maximum = vim.system, 0, 0, 0
vim.system = function(cmd, opts, callback)
    starts = starts + 1; workers = workers + 1; maximum = math.max(maximum, workers)
    return real_system(cmd, opts, function(result)
        workers = workers - 1; callback(result)
    end)
end
local unwanted, result = false, nil
local cancel = parser.request(root .. '/rtl/a.sv', root, function() unwanted = true end)
cancel()
parser.request(root .. '/rtl/b.v', root, function(r) result = r end)
wait(function() return result ~= nil end, 'parser timeout')
assert(not unwanted and maximum == 1 and not result.error and #result.modules == 2, vim.inspect(result))
local count = starts; result = nil
parser.request(root .. '/rtl/b.v', root, function(r) result = r end)
assert(result and starts == count, 'memory cache missed')
parser.invalidate(root .. '/rtl/b.v'); result = nil
parser.request(root .. '/rtl/b.v', root, function(r) result = r end)
wait(function() return result end, 'invalidation timeout'); assert(starts == count + 1)
write('rtl/b.v', { 'module changed; endmodule' }); result = nil
parser.request(root .. '/rtl/b.v', root, function(r) result = r end)
wait(function() return result end, 'stat invalidation timeout'); assert(result.modules[1].name == 'changed')
write('rtl/b.v', { 'module broken (' }); result = nil
parser.request(root .. '/rtl/b.v', root, function(r) result = r end)
wait(function() return result end, 'error timeout'); assert(result.error)
write('rtl/b.v', { 'module good; endmodule', 'module unsupported(a); input a; endmodule' }); result = nil
parser.request(root .. '/rtl/b.v', root, function(r) result = r end)
wait(function() return result end, 'mixed sibling timeout')
assert(not result.error and #result.modules == 1 and #result.warnings == 1)
vim.system = real_system
local instance = require('hdl.instance')
local bin = vim.fn.expand('~/.local/share/nvim/mason/bin/verible-verilog-syntax')
local function parse(source)
    local r = vim.system({ bin, '--export_json', '--printtree', '-' }, { stdin = source, text = true }):wait()
    assert(r.code == 0, r.stderr)
    return instance.parse(source, vim.json.decode(r.stdout)['-'], 'fixture.sv')
end
for _, declaration in ipairs({ 'parameter logic [63:0] W=64\'hffffffffffffffff', 'parameter real W=1.5', 'parameter W=other', 'parameter int W=8, localparam X=2' }) do
    local mods = parse('module dut #(' .. declaration .. ')(input logic a); endmodule')
    assert(#mods == 1)
    assert(not pcall(instance.render_testbench, mods[1]), 'unsafe TB accepted: ' .. declaration)
end
local mods = parse('module dut #(parameter int W=8)(input logic [W-1:0] a); endmodule')
assert(table.concat(instance.render_testbench(mods[1]), '\n'):find('localparam int W = 8;', 1, true))
-- Real Telescope lifecycle and delayed previews (no user project files).
for _, package in ipairs({ 'plenary.nvim', 'telescope.nvim' }) do
    vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/site/pack/core/opt/' .. package)
end
vim.o.columns = 160; vim.o.lines = 45
require('telescope').setup({ defaults = { sorting_strategy = 'ascending' } })
write('rtl/b.v', { 'module b; endmodule', 'module c; endmodule' })
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(buf, root .. '/tb/current.sv')
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '// insert' })
local state, actions = require('telescope.actions.state'), require('telescope.actions')
local function picker()
    local p
    wait(function()
        local good, value = pcall(state.get_current_picker, vim.api.nvim_get_current_buf())
        if good and value and value.manager and value.manager:num_results() > 0 then p = value; return true end
    end, 'picker missing')
    return p
end
local function preview(p, text)
    wait(function()
        local b = p.previewer.state.bufnr
        return b and vim.api.nvim_buf_is_valid(b) and table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), '\n'):find(text, 1, true)
    end, 'missing preview: ' .. text)
end
instance.open(); local p = picker()
actions.select_default(p.prompt_bufnr)
assert(vim.api.nvim_buf_line_count(buf) == 1, 'loading Enter inserted')
p:set_selection(1); preview(p, 'u_b')
actions.select_default(p.prompt_bufnr); p = picker(); assert(p.manager:num_results() == 2)
preview(p, 'u_b'); actions.select_default(p.prompt_bufnr)
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('b u_b', 1, true))
local count_lines = vim.api.nvim_buf_line_count(buf)
instance.open(); p = picker(); p:set_selection(1); p:set_selection(0); preview(p, 'u_a')
actions.close(p.prompt_bufnr); vim.wait(250)
assert(vim.api.nvim_buf_line_count(buf) == count_lines, 'cancel changed target')
instance.open(); p = picker() -- Real mapped Escape during debounce.
for _, mode in ipairs({ 'i', 'n' }) do
    local mapping = vim.fn.maparg('<Esc>', mode, false, true)
    assert(mapping.buffer == 1 and mapping.callback, 'missing picker Escape mapping: ' .. mode)
end
vim.cmd.stopinsert()
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'xt', false)
wait(function() return not vim.api.nvim_buf_is_valid(p.prompt_bufnr) end, 'Escape did not close picker')
vim.wait(250)
instance.open_testbench(); p = picker(); preview(p, 'module a_tb;'); actions.select_default(p.prompt_bufnr)
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('module a_tb;', 1, true))
-- One unrenderable TB sibling must not hide the supported sibling.
write('rtl/b.v', { 'module bad(inout wire x); endmodule', 'module good; endmodule' })
instance.open_testbench(); p = picker(); p:set_selection(1); preview(p, 'module good_tb;')
actions.select_default(p.prompt_bufnr); p = picker(); assert(p.manager:num_results() == 2)
preview(p, 'inout testbench driving is not supported')
local before_bad = vim.api.nvim_buf_line_count(buf)
actions.select_default(p.prompt_bufnr); assert(vim.api.nvim_buf_line_count(buf) == before_bad)
p:set_selection(1); preview(p, 'module good_tb;'); actions.select_default(p.prompt_bufnr)
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('module good_tb;', 1, true))
write('rtl/b.v', { 'module b; endmodule', 'module c; endmodule' })
-- Delay real parser completion beyond focus change/close, not a fake CST.
parser.invalidate(root .. '/rtl/a.sv'); parser.invalidate(root .. '/rtl/b.v')
local delayed = 0
vim.system = function(cmd, opts, callback)
    return real_system(cmd, opts, function(r)
        delayed = delayed + 1
        vim.defer_fn(function() callback(r) end, 350)
    end)
end
instance.open(); p = picker(); p:set_selection(0)
wait(function() return delayed > 0 end, 'delayed parser did not finish: ' .. vim.inspect(notices))
p:set_selection(1); preview(p, 'u_b')
assert(not table.concat(vim.api.nvim_buf_get_lines(p.previewer.state.bufnr, 0, -1, false), '\n'):find('u_a', 1, true), 'stale preview won')
actions.close(p.prompt_bufnr)
parser.invalidate(root .. '/rtl/a.sv'); delayed = 0
instance.open(); p = picker(); p:set_selection(0)
wait(function() return delayed > 0 end, 'close-race parser did not finish')
actions.close(p.prompt_bufnr); vim.wait(500)
vim.system = real_system

-- Excluded unsaved TB must still be linted alongside RTL, and repaired
-- diagnostics are checked only after a real second process has completed.
write('.hdl-sources', { 'rtl/a.sv' }); assert(not scan())
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'module current;', 'logic x, y;', 'a dut(.a(x), .z(y));',
    'initial begin x = nonexistent_signal; #1; $finish; end', 'endmodule',
})
vim.b[buf].verilator_top_module = 'current'
vim.b[buf].verilator_lint_args = { '--Wno-fatal' }
local completed = 0
vim.system = function(cmd, opts, callback)
    return real_system(cmd, opts, function(r)
        callback(r); vim.schedule(function() completed = completed + 1 end)
    end)
end
local lint = require('lsp.verilator_lint')
local lint_ns = vim.api.nvim_get_namespaces()['verilator-lint']
lint.run(root, buf)
wait(function() return completed == 1 end, 'first lint did not complete')
local diagnostics = vim.diagnostic.get(buf, { namespace = lint_ns })
assert(#diagnostics > 0 and vim.inspect(diagnostics):find('nonexistent_signal', 1, true), 'excluded TB was not linted')
vim.api.nvim_buf_set_lines(buf, 3, 4, false, { 'initial begin x = 0; #1; $display("%b", y); $finish; end' })
lint.run(root, buf)
wait(function() return completed == 2 end, 'repaired lint did not complete')
for _, diagnostic in ipairs(vim.diagnostic.get(buf, { namespace = lint_ns })) do
    assert(diagnostic.severity ~= vim.diagnostic.severity.ERROR, vim.inspect(diagnostic))
end
assert(vim.fn.filereadable(root .. '/tb/current.sv') == 0, 'lint wrote unsaved TB to disk')
assert(vim.deep_equal(vim.fn.readfile(root .. '/verible.filelist'), { 'rtl/a.sv' }))
vim.api.nvim_buf_set_name(buf, root .. '/build/current.sv')
lint.run(root, buf)
wait(function() return completed == 3 end, 'build TB lint did not complete')
for _, diagnostic in ipairs(vim.diagnostic.get(buf, { namespace = lint_ns })) do
    assert(diagnostic.severity ~= vim.diagnostic.severity.ERROR, vim.inspect(diagnostic))
end
assert(vim.fn.filereadable(root .. '/build/current.sv') == 0)
vim.system = real_system
vim.fn.delete(root, 'rf')
print('HDL scopes, atomic preservation, stale jobs/previews, real parser/cache/cancellation, conservative TB, Telescope lifecycle, excluded unsaved TB lint: PASS')
vim.cmd('qa!')
