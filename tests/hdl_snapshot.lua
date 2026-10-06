-- nvim --headless -u NONE -i NONE -l tests/hdl_snapshot.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local uv = vim.uv
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/rtl', 'p')
root = assert(uv.fs_realpath(root))
local old_cwd = vim.fn.getcwd()
vim.cmd.cd(vim.fn.fnameescape(root))
local disk_rtl = { 'module dut(output logic y); assign y = 0; endmodule' }
vim.fn.writefile(disk_rtl, root .. '/rtl/dut.sv')
vim.fn.writefile({ 'rtl/dut.sv', 'rtl/new.sv' }, root .. '/verible.filelist')
local function buffer(path, content)
    local buf = vim.api.nvim_create_buf(true, false)
    if path then vim.api.nvim_buf_set_name(buf, path) end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content or { '' })
    return buf
end
local rtl = buffer(root .. '/rtl/dut.sv', { 'module dut(output logic y); assign y = 1; endmodule' })
local new = buffer(root .. '/rtl/new.sv', { 'module helper(output logic y); assign y = 1; endmodule' })
local source = buffer(root .. '/top.sv', {
    'module top;', 'wire a, b;', 'dut u_dut(.y(a));', 'helper u_helper(.y(b));',
    'initial begin #1; $display("%b %b", a, b); $finish; end', 'endmodule',
})
vim.b[source].verilator_top_module = 'top'
vim.b[source].verilator_lint_args = { '--Wno-fatal' }
vim.api.nvim_set_current_buf(source)
local notices, snapshots, completed = {}, {}, 0
local real_notify, real_system = vim.notify, vim.system
vim.notify = function(message, level)
    if level == vim.log.levels.ERROR then notices[#notices + 1] = message end
end
vim.system = function(cmd, opts, callback)
    assert(cmd[1] == 'verilator')
    -- Inspect the actual snapshot before Verilator runs, then use the real tool.
    assert(uv.fs_stat(opts.cwd).type == 'directory', 'snapshot root was replaced')
    assert(uv.fs_stat(opts.cwd .. '/rtl').type == 'directory', 'directory buffer replaced snapshot directory')
    for _, buf in ipairs({ rtl, new, source }) do
        local relative = vim.api.nvim_buf_get_name(buf):sub(#root + 2)
        assert(vim.deep_equal(vim.fn.readfile(opts.cwd .. '/' .. relative),
            vim.api.nvim_buf_get_lines(buf, 0, -1, false)), 'missing unsaved overlay: ' .. relative)
        assert(uv.fs_lstat(opts.cwd .. '/' .. relative).type == 'file', 'overlay still a symlink')
    end
    snapshots[#snapshots + 1] = opts.cwd
    return real_system(cmd, opts, function(result)
        callback(result)
        vim.schedule(function() completed = completed + 1 end)
    end)
end
local lint = require('lsp.verilator_lint')
local ns = vim.api.nvim_get_namespaces()['verilator-lint']
local function run()
    local expected = completed + 1
    lint.run(root, source)
    assert(vim.wait(10000, function() return completed == expected or #notices > 0 end, 10), 'lint timed out')
    assert(#notices == 0, table.concat(notices, '\n'))
    for _, buf in ipairs({ rtl, new, source }) do
        for _, diagnostic in ipairs(vim.diagnostic.get(buf, { namespace = ns })) do
            assert(diagnostic.severity ~= vim.diagnostic.severity.ERROR, vim.inspect(diagnostic))
        end
    end
    assert(not uv.fs_stat(snapshots[#snapshots]), 'snapshot not cleaned up')
    assert(vim.deep_equal(vim.fn.readfile(root .. '/rtl/dut.sv'), disk_rtl), 'lint modified saved RTL')
    assert(not uv.fs_stat(root .. '/rtl/new.sv') and not uv.fs_stat(root .. '/top.sv'), 'lint saved new buffers')
end
local ok, err = xpcall(function()
    assert(vim.fn.executable('verilator') == 1, 'Verilator is required')
    local unnamed = buffer(nil, { 'unsaved notes' })
    run()
    vim.api.nvim_buf_delete(unnamed, { force = true })
    local directory = buffer(root .. '/rtl', { 'directory view' })
    run()
    vim.api.nvim_buf_delete(directory, { force = true })
    local project_directory = buffer(root, { 'project directory view' })
    run()
    vim.api.nvim_buf_delete(project_directory, { force = true })
    assert(uv.fs_symlink(root .. '/rtl', root .. '/linked_dir'))
    local linked_directory = buffer(root .. '/linked_dir', { 'symlink directory view' })
    run()
    vim.api.nvim_buf_delete(linked_directory, { force = true })
end, debug.traceback)
vim.notify, vim.system = real_notify, real_system
vim.cmd.cd(vim.fn.fnameescape(old_cwd))
vim.fn.delete(root, 'rf')
if not ok then error(err) end
print('HDL snapshot: unnamed/directory buffers skipped, named unsaved overlays, real lint, disk preservation, cleanup: PASS')
vim.cmd('qa!')
