-- nvim --headless -u NONE -i NONE -l tests/formatting.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/site/pack/core/opt/conform.nvim')
vim.env.PATH = vim.fn.stdpath('data') .. '/mason/bin:' .. vim.env.PATH
vim.g.mapleader = ' '
require('plugins.formatting')
local conform = require('conform')
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local normal = vim.fn.maparg('<leader>f', 'n', false, true).callback
local visual = vim.fn.maparg('<leader>f', 'x', false, true).callback
assert(normal and visual, 'normal/visual mappings missing')
local calls, done, failure, last_opts = 0, false, nil, nil
local real_format = conform.format
conform.format = function(opts)
    calls = calls + 1; done = false; failure = nil; last_opts = opts
    return real_format(opts, function(err) failure = err; done = true end)
end
local function wait()
    assert(vim.wait(10000, function() return done end, 10), 'formatter timed out')
    assert(not failure, vim.inspect(failure))
end
local function lines()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end
local function escape()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
end
local function fixture(name, ft, text)
    escape()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_name(buf, root .. '/' .. name)
    vim.bo.filetype = ft
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
    vim.cmd('let &undolevels = &undolevels')
    return buf
end
local function selection(mode, first, last)
    vim.api.nvim_win_set_cursor(0, first)
    vim.cmd.normal({ mode, bang = true })
    vim.api.nvim_win_set_cursor(0, last)
    visual(); wait()
    escape()
end
local python = {
    'import sys', 'import os', '', '',
    'def selected( ):', '    value=  [1,2,3]', '    return value', '', '',
    'def untouched( ):', '    result=  [4,5,6]', '    return result',
}
local hdl = {
    'module sample;',
    '  logic a;', '  logic b;', '  logic c;', '',
    'assign a=1;', '',
    'assign b=0;', '',
    'assign c=1;',
    'endmodule',
}
local ok, err = xpcall(function()
    assert(vim.fn.executable('ruff') == 1, 'Ruff is required')
    assert(vim.fn.executable('verible-verilog-format') == 1, 'Verible is required')
    -- Native Verible range arguments must retain the existing alignment setting.
    local config = assert(conform.get_formatter_config('verible', 0))
    local args = config.range_args(config, { range = { start = { 6, 0 }, ['end'] = { 6, 10 } } })
    assert(vim.tbl_contains(args, '--lines=6-6'))
    assert(vim.tbl_contains(args, '--port_declarations_alignment=align'))

    fixture('forward.py', 'python', python)
    selection('V', { 5, 0 }, { 7, 0 })
    assert(vim.deep_equal(last_opts.formatters, { 'ruff_format' }), 'selection organizes imports')
    local result = lines()
    assert(result[5] == 'def selected():' and result[6] == '    value = [1, 2, 3]', vim.inspect(result))
    for _, i in ipairs({ 1, 2, 3, 4, 8, 9, 10, 11, 12 }) do
        assert(result[i] == python[i], 'Python changed outside selection: ' .. i)
    end
    vim.cmd.undo()
    assert(vim.deep_equal(lines(), python), 'selection must be undoable in one step')
    assert(vim.fn.filereadable(root .. '/forward.py') == 0, 'formatter saved buffer')

    fixture('reverse.py', 'python', python)
    selection('V', { 7, 0 }, { 5, 0 })
    assert(vim.deep_equal(lines(), result), 'reverse line selection differs')

    fixture('characters.py', 'python', python)
    selection('v', { 6, #python[6] - 1 }, { 6, 4 })
    assert(lines()[6] == '    value = [1, 2, 3]', 'character selection not formatted')
    assert(lines()[11] == python[11] and lines()[1] == python[1], 'character selection changed distant code')

    for _, ft in ipairs({ 'systemverilog', 'verilog' }) do
        fixture('selection.' .. (ft == 'verilog' and 'v' or 'sv'), ft, hdl)
        selection('V', { 8, 0 }, { 8, 0 })
        local formatted = lines()
        assert(formatted[8] == '  assign b=0;', vim.inspect(formatted))
        for i, line in ipairs(hdl) do
            if i ~= 8 then assert(formatted[i] == line, 'Verible changed outside selected line: ' .. i) end
        end
    end

    -- Blockwise must never fall through to full-buffer formatting.
    local before, count = lines(), calls
    vim.api.nvim_win_set_cursor(0, { 6, 0 })
    vim.cmd.normal({ string.char(22), bang = true })
    vim.api.nvim_win_set_cursor(0, { 8, 4 })
    visual(); escape()
    assert(calls == count and vim.deep_equal(before, lines()), 'block selection formatted the file')

    fixture('whole.py', 'python', python)
    normal(); wait()
    assert(not last_opts.formatters and not last_opts.range, 'normal mapping must use default whole-buffer chain')
    local whole = table.concat(lines(), '\n')
    assert(whole:find('import os\nimport sys', 1, true), 'normal mode no longer organizes imports')
    assert(whole:find('    result = [4, 5, 6]', 1, true), 'normal mode did not format entire buffer')

    -- Unconfigured filetypes retain range-aware LSP fallback via Conform.
    fixture('plain.txt', 'text', { 'unchanged' })
    vim.cmd.normal({ 'V', bang = true })
    visual()
    assert(vim.wait(10000, function() return done end, 10))
    escape()
    assert(failure == 'No formatters available for buffer', 'unexpected no-server behavior')
    assert(last_opts.lsp_format == 'fallback' and not last_opts.formatters)
    assert(lines()[1] == 'unchanged')
end, debug.traceback)
escape()
vim.fn.delete(root, 'rf')
if not ok then error(err) end
print('Formatting: real Ruff/Verible ranges, forward/reverse/character selections, imports, undo, block guard, normal mode: PASS')
vim.cmd('qa!')
