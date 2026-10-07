-- Event wiring regression; real Verilator execution is covered in tests/hdl.lua.
-- nvim --headless -u NONE -l tests/hdl_open.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/.git', 'p')
vim.fn.writefile({ 'module dut; endmodule' }, root .. '/dut.sv')
vim.fn.writefile({ 'dut.sv' }, root .. '/verible.filelist')
local calls = {}
package.loaded['lsp.verilator_lint'] = {
    run = function(project, buf) calls[#calls + 1] = { project = project, buf = buf } end,
}
local sources = require('hdl.sources')
local real_scan = sources.scan
sources.scan = function() error('opening a source must never scan') end
require('lsp.hdl')
vim.lsp.enable('verible', false)
vim.cmd.edit(vim.fn.fnameescape(root .. '/dut.sv'))
assert(#calls == 1 and calls[1].buf == vim.api.nvim_get_current_buf(), 'open did not lint')
for _, suffix in ipairs({ 'Sources', 'Instance', 'Testbench' }) do
    assert(vim.fn.exists(':RTL' .. suffix) == 2, 'missing RTL command: ' .. suffix)
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
-- Saving the new filename must trigger a real scan; it alone identifies a root.
local scan_count, scan_done, scan_error = 0, false, nil
sources.scan = function(project, silent)
    scan_count = scan_count + 1
    real_scan(project, silent, function(err) scan_done, scan_error = true, err end)
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'dut.sv' })
vim.cmd.write()
assert(vim.wait(5000, function() return scan_done end, 10), 'saving .rtl-sources did not scan')
assert(scan_count == 1 and not scan_error, tostring(scan_error))
assert(vim.deep_equal(vim.fn.readfile(root .. '/verible.filelist'), { 'dut.sv' }))
vim.fn.delete(root .. '/.git', 'rf')
assert(vim.uv.fs_realpath(sources.root()) == vim.uv.fs_realpath(root), '.rtl-sources root marker not found')
vim.api.nvim_exec_autocmds('BufWritePost', { pattern = root .. '/.hdl-sources' })
assert(scan_count == 1, 'old filename still triggers scanning')
sources.scan = function() error('opening a source must never scan') end
vim.api.nvim_win_close(0, true)
vim.api.nvim_set_current_win(original_win)
vim.api.nvim_exec_autocmds('BufEnter', { buffer = 0 })
assert(#calls == 1, 'switching buffers must not lint')
local preview = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(preview, root .. '/preview.sv')
vim.api.nvim_exec_autocmds('BufReadPost', { buffer = preview })
assert(#calls == 1, 'scratch/preview must not lint')
vim.fn.delete(root .. '/verible.filelist')
vim.api.nvim_exec_autocmds('BufReadPost', { buffer = 0 })
assert(#calls == 1, 'missing filelist must not lint or scan')
local notify, message = vim.notify, nil
vim.notify = function(text) message = text end
require('hdl.picker').open(function() end, 'Test')
vim.notify = notify
assert(message and message:find(':RTLSources', 1, true), 'missing-filelist hint uses old command')
vim.fn.delete(root, 'rf')
print('RTL commands, instance mapping, sources float, missing-filelist hint, HDL open event guards: PASS')
vim.cmd('qa!')
