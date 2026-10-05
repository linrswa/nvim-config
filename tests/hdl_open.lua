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
sources.scan = function() error('opening a source must never scan') end
require('lsp.hdl')
vim.lsp.enable('verible', false)
vim.cmd.edit(vim.fn.fnameescape(root .. '/dut.sv'))
assert(#calls == 1 and calls[1].buf == vim.api.nvim_get_current_buf(), 'open did not lint')
vim.api.nvim_exec_autocmds('BufEnter', { buffer = 0 })
assert(#calls == 1, 'switching buffers must not lint')
local preview = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(preview, root .. '/preview.sv')
vim.api.nvim_exec_autocmds('BufReadPost', { buffer = preview })
assert(#calls == 1, 'scratch/preview must not lint')
vim.fn.delete(root .. '/verible.filelist')
vim.api.nvim_exec_autocmds('BufReadPost', { buffer = 0 })
assert(#calls == 1, 'missing filelist must not lint or scan')
vim.fn.delete(root, 'rf')
print('HDL open event, normal-buffer guard, no enter rescan, missing filelist: PASS')
vim.cmd('qa!')
