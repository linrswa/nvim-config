-- nvim --headless -u NONE -l tests/path_picker.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
for _, package in ipairs({ 'plenary.nvim', 'telescope.nvim' }) do
    vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/site/pack/core/opt/' .. package)
end
vim.o.columns = 160; vim.o.lines = 45
vim.g.mapleader = ' '
require('plugins.telescope')
require('telescope').setup({ defaults = { sorting_strategy = 'ascending' } })
local root = vim.fn.tempname()
local fallback = vim.fn.tempname()
local original_cwd = vim.fn.getcwd()
local function write(path, lines)
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    vim.fn.writefile(lines or { 'fixture' }, path)
end
write(root .. '/.git/config')
write(root .. '/src/hello world.sv')
write(root .. '/src/中文.lua')
write(root .. '/.hidden')
write(root .. '/.ignored/file.txt')
write(root .. '/.gitignore', { '.ignored/' })
write(root .. '/build/generated.sv')
write(root .. '/node_modules/package/index.js')
vim.fn.mkdir(root .. '/empty', 'p')
assert(vim.uv.fs_symlink(root, root .. '/cycle'))
assert(vim.uv.fs_symlink(root .. '/src/hello world.sv', root .. '/linked.sv'))
write(fallback .. '/fallback.txt')
local module = require('plugins.path_picker')
local state, actions = require('telescope.actions.state'), require('telescope.actions')
local function wait(check, message)
    assert(vim.wait(5000, check, 10), message)
end
local function picker()
    local p
    wait(function()
        local ok, value = pcall(state.get_current_picker, vim.api.nvim_get_current_buf())
        if ok and value and value.manager and value.manager:num_results() > 0 then p = value; return true end
    end, 'picker has no results')
    return p
end
local function select(p, path)
    for i = 1, p.manager:num_results() do
        if p.manager:get_entry(i).value == path then p:set_selection(i - 1); return end
    end
    error('missing path: ' .. path)
end
local function current(buf)
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end
local ok, err = xpcall(function()
    vim.cmd.edit(vim.fn.fnameescape(root .. '/notes.md'))
    local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
    local map = vim.fn.maparg('<leader>fp', 'n', false, true)
    assert(map.callback and map.buffer == 0, 'global mapping missing')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '路徑 = ""' })
    -- End the fixture undo block so one undo must only remove the pasted text.
    vim.cmd('let &undolevels = &undolevels')
    vim.api.nvim_win_set_cursor(win, { 1, #'路徑 = "' })
    vim.fn.setreg('"', 'clipboard sentinel')
    local register = vim.fn.getreg('"')
    map.callback()
    local p = picker()
    assert(p.cache_picker == false, 'one-shot picker must not be resumable')
    assert(p.prompt_title:find(root, 1, true), 'wrong project root')
    local entries = {}
    for entry in p.manager:iter() do entries[entry.value] = true end
    assert(entries['src/'] and entries['empty/'] and entries['src/中文.lua'])
    assert(entries['.hidden'] and entries['.ignored/file.txt'], 'hidden/ignored policy mismatch')
    assert(not entries['.git/'] and not entries['build/'] and not entries['node_modules/'])
    assert(not entries['cycle/'] and not entries['linked.sv'], 'symlink included')
    select(p, 'src/hello world.sv')
    actions.select_default(p.prompt_bufnr)
    for _, cached in ipairs(require('telescope.state').get_global_key('cached_pickers') or {}) do
        assert(cached ~= p, 'closed picker cached a stale insertion callback')
    end
    assert(current(buf) == '路徑 = "src/hello world.sv"', 'wrong insertion location: ' .. current(buf))
    assert(vim.api.nvim_get_current_win() == win, 'original window not restored')
    assert(vim.fn.getreg('"') == register, 'register changed')
    assert(vim.fn.filereadable(root .. '/notes.md') == 0, 'target saved automatically')
    vim.cmd.undo()
    assert(current(buf) == '路徑 = ""', 'one undo did not restore target')

    -- Float target, as used by :HdlSources, without requiring any HDL code.
    local floatbuf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(floatbuf, root .. '/.hdl-sources')
    local float = vim.api.nvim_open_win(floatbuf, true, {
        relative = 'editor', width = 70, height = 12, row = 2, col = 2, border = 'rounded',
    })
    module.open(); p = picker(); select(p, 'src/'); actions.select_default(p.prompt_bufnr)
    assert(current(floatbuf) == 'src/' and vim.api.nvim_get_current_win() == float, 'float/folder paste failed')
    local before = current(floatbuf)
    module.open(); p = picker()
    local escape = vim.fn.maparg('<Esc>', 'n', false, true)
    assert(escape.callback, 'Escape mapping missing'); escape.callback()
    vim.wait(30)
    assert(current(floatbuf) == before, 'cancel changed buffer')
    -- Cancel before discovery finishes, then immediately reopen.
    module.open()
    actions.close(vim.api.nvim_get_current_buf())
    module.open(); p = picker(); actions.close(p.prompt_bufnr)
    assert(current(floatbuf) == before, 'early cancel changed buffer')

    -- Target becomes unmodifiable while picker is open.
    module.open(); p = picker(); vim.bo[floatbuf].modifiable = false
    actions.select_default(p.prompt_bufnr)
    assert(current(floatbuf) == before, 'modified unavailable target')
    module.open()
    assert(vim.api.nvim_get_current_buf() == floatbuf, 'opened on unmodifiable buffer')
    vim.bo[floatbuf].modifiable = true
    module.open(); p = picker()
    vim.api.nvim_win_close(float, true)
    actions.select_default(p.prompt_bufnr)
    assert(current(floatbuf) == before, 'closed-window target was modified')
    vim.api.nvim_set_current_win(win)

    -- Unnamed buffer falls back to cwd; no HDL-specific root dependency.
    vim.cmd.cd(vim.fn.fnameescape(fallback))
    vim.cmd.enew()
    module.open(); p = picker()
    assert(p.prompt_title:find(fallback, 1, true), 'cwd fallback failed')
    select(p, 'fallback.txt'); actions.select_default(p.prompt_bufnr)
    assert(current(0) == 'fallback.txt', 'unnamed-buffer paste failed')

    -- Empty results: Enter is harmless and Escape still releases the session.
    vim.fn.mkdir(fallback .. '/empty', 'p')
    vim.cmd.cd(vim.fn.fnameescape(fallback .. '/empty'))
    module.open()
    p = state.get_current_picker(vim.api.nvim_get_current_buf())
    vim.wait(50)
    actions.select_default(p.prompt_bufnr)
    actions.close(p.prompt_bufnr)
    assert(current(0) == 'fallback.txt', 'empty selection changed target')
end, debug.traceback)
vim.cmd.cd(vim.fn.fnameescape(original_cwd))
vim.fn.delete(root, 'rf'); vim.fn.delete(fallback, 'rf')
if not ok then error(err) end
print('Find/paste path: discovery, global mapping, file/folder, Unicode, undo, float, cancel, guards, cwd: PASS')
vim.cmd('qa!')
