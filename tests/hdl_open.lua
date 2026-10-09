-- Event wiring regression; real scanning/lint execution is covered in tests/hdl.lua.
-- nvim --headless -u NONE -i NONE -l tests/hdl_open.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/.git', 'p')
root = vim.uv.fs_realpath(root)
vim.fn.writefile({ 'module dut; endmodule' }, root .. '/dut.sv')
vim.fn.writefile({ 'dut.sv' }, root .. '/verible.filelist')
local calls, invalidated = {}, {}
package.loaded['lsp.verilator_lint'] = {
    run = function(project, buf)
        calls[#calls + 1] = { kind = 'run', project = project, buf = buf }
    end,
    refresh = function(project, buf, silent)
        calls[#calls + 1] = { kind = 'refresh', project = project, buf = buf, silent = silent }
    end,
}
package.loaded['hdl.parser'] = {
    invalidate = function(path) invalidated[#invalidated + 1] = path end,
}
local sources = require('hdl.sources')
-- All scans must go through the mocked shared refresh API, never directly.
sources.scan = function() error('event/command bypassed lint.refresh') end
require('lsp.hdl')
vim.lsp.enable('verible', false)
local function expect(kind, buf, silent, label)
    assert(#calls == 1, label .. ': expected one call, got ' .. vim.inspect(calls))
    assert(vim.deep_equal(calls[1], { kind = kind, project = root, buf = buf, silent = silent }),
        label .. ': unexpected dispatch ' .. vim.inspect(calls[1]))
end
local function event(name, buf, kind, target)
    calls = {}
    vim.api.nvim_exec_autocmds(name, { buffer = buf })
    if kind then
        expect(kind, target, kind == 'refresh' and true or nil, name)
    else
        assert(#calls == 0, name .. ': unexpected dispatch ' .. vim.inspect(calls))
    end
end
vim.cmd.edit(vim.fn.fnameescape(root .. '/dut.sv'))
local dut = vim.api.nvim_get_current_buf()
-- A real open can produce both BufReadPost and BufEnter; both now request lint.
assert(#calls > 0, 'open did not lint')
for _, call in ipairs(calls) do
    assert(call.kind == 'run' and call.project == root and call.buf == dut, 'open dispatch failed')
end
for _, name in ipairs({ 'RTLSources', 'RTLInstance', 'RTLTestbench', 'VeribleScan', 'VerilatorLint' }) do
    assert(vim.fn.exists(':' .. name) == 2, 'missing command: ' .. name)
end
for _, suffix in ipairs({ 'Sources', 'Instance', 'Testbench' }) do
    assert(vim.fn.exists(':Hdl' .. suffix) == 0, 'legacy command still registered: ' .. suffix)
end
local instance_calls = {}
package.loaded['hdl.instance'] = {
    open = function() instance_calls[#instance_calls + 1] = 'instance' end,
    open_testbench = function() instance_calls[#instance_calls + 1] = 'testbench' end,
}
vim.cmd.RTLInstance()
vim.cmd.RTLTestbench()
assert(vim.deep_equal(instance_calls, { 'instance', 'testbench' }), 'RTL command dispatch failed')
for _, ft in ipairs({ 'verilog', 'systemverilog' }) do
    vim.bo.filetype = ft
    local mapping = vim.fn.maparg('<leader>fi', 'n', false, true)
    assert(mapping.buffer == 1 and mapping.rhs == '<cmd>RTLInstance<CR>', 'instance mapping uses old command')
end
local original_win = vim.api.nvim_get_current_win()
vim.cmd.RTLSources()
assert(vim.fs.basename(vim.api.nvim_buf_get_name(0)) == '.rtl-sources', 'RTLSources opened wrong buffer')
assert(vim.api.nvim_win_get_config(0).relative == 'editor', 'RTLSources did not open a float')
assert(vim.fn.filereadable(root .. '/.rtl-sources') == 0, 'RTLSources unexpectedly saved the spec')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'dut.sv' })
calls = {}
vim.cmd.write()
expect('refresh', nil, true, 'scope save')
-- The spec alone identifies the project, even without a VCS root marker.
vim.fn.delete(root .. '/.git', 'rf')
assert(vim.uv.fs_realpath(sources.root()) == root, '.rtl-sources root marker not found')
calls = {}
vim.api.nvim_exec_autocmds('BufWritePost', { pattern = root .. '/.hdl-sources' })
assert(#calls == 0, 'old filename still triggers refresh')
for _, command in ipairs({ 'VeribleScan', 'VeribleScan!', 'VerilatorLint' }) do
    calls = {}
    vim.cmd(command)
    expect('refresh', nil, command ~= 'VeribleScan', command .. ' from scope buffer')
end
vim.api.nvim_win_close(0, true)
vim.api.nvim_set_current_win(original_win)
local refresh_events = { 'BufReadPost', 'BufEnter', 'BufNewFile', 'BufFilePost',
    'FocusGained', 'TermLeave', 'BufWritePost' }
local text_events = { 'TextChanged', 'TextChangedI', 'TextChangedP' }
for _, name in ipairs(refresh_events) do event(name, dut, 'refresh', dut) end
assert(invalidated[#invalidated] == root .. '/dut.sv', 'save did not invalidate parser')
for _, name in ipairs(text_events) do event(name, dut, 'run', dut) end
for _, command in ipairs({ 'VeribleScan', 'VeribleScan!', 'VerilatorLint' }) do
    calls = {}
    vim.cmd(command)
    expect('refresh', dut, command ~= 'VeribleScan', command)
end
-- Without a filelist, even a text event must bootstrap it through refresh.
vim.fn.delete(root .. '/verible.filelist')
for _, name in ipairs(refresh_events) do event(name, dut, 'refresh', dut) end
for _, name in ipairs(text_events) do event(name, dut, 'refresh', dut) end
vim.fn.writefile({ 'dut.sv' }, root .. '/verible.filelist')
-- Named scratch/instance-preview buffers must never be submitted as HDL targets.
local preview = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(preview, root .. '/preview.sv')
local invalidation_count = #invalidated
for _, name in ipairs({ 'BufReadPost', 'BufEnter', 'BufNewFile', 'BufFilePost',
    'BufWritePost', 'TextChanged', 'TextChangedI', 'TextChangedP' }) do
    event(name, preview)
end
assert(#invalidated == invalidation_count, 'scratch save invalidated parser')
vim.api.nvim_set_current_buf(preview)
-- A scratch filename does not establish a project root for focus/terminal return.
for _, name in ipairs({ 'FocusGained', 'TermLeave' }) do event(name, preview) end
local note = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(note, root .. '/notes.txt')
vim.api.nvim_set_current_buf(note)
for _, name in ipairs({ 'FocusGained', 'TermLeave' }) do event(name, note, 'refresh', nil) end
vim.api.nvim_set_current_buf(dut)
-- All supported HDL extensions participate in event-triggered refresh.
for _, ext in ipairs({ 'v', 'svh', 'vh' }) do
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, root .. '/header.' .. ext)
    event('BufReadPost', buf, 'refresh', buf)
    event('TextChanged', buf, 'run', buf)
end
-- Keep a root marker while checking the legacy filelist-only fallback.
vim.fn.mkdir(root .. '/.git', 'p')
vim.fn.delete(root .. '/.rtl-sources')
for _, name in ipairs(refresh_events) do event(name, dut, 'run', dut) end
for _, name in ipairs(text_events) do event(name, dut, 'run', dut) end
calls = {}
vim.cmd.VerilatorLint()
expect('run', dut, nil, 'manual filelist-only lint')
vim.fn.delete(root .. '/verible.filelist')
for _, name in ipairs(refresh_events) do event(name, dut) end
for _, name in ipairs(text_events) do event(name, dut) end
local notify, message = vim.notify, nil
vim.notify = function(text) message = text end
require('hdl.picker').open(function() end, 'Test')
vim.notify = notify
assert(message and message:find(':RTLSources', 1, true), 'missing-filelist hint uses old command')
vim.fn.delete(root, 'rf')
print('RTL commands, scope float/save, shared refresh dispatch, HDL event guards: PASS')
vim.cmd('qa!')
