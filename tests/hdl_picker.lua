-- nvim --headless -u NONE -i NONE -l tests/hdl_picker.lua
-- Real Telescope/Verible, including layouts where define_preview is never called.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
for _, package in ipairs({ 'plenary.nvim', 'telescope.nvim' }) do
    vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/site/pack/core/opt/' .. package)
end
vim.o.columns = 80; vim.o.lines = 24
require('telescope').setup({ defaults = {
    sorting_strategy = 'ascending', layout_strategy = 'horizontal',
    layout_config = { horizontal = { preview_cutoff = 100 } },
} })
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/rtl', 'p')
root = assert(vim.uv.fs_realpath(root))
local function write(name, lines) vim.fn.writefile(lines, root .. '/' .. name) end
write('.rtl-sources', { 'rtl/' })
write('rtl/a.sv', { 'module a(input logic x, output logic y); assign y = x; endmodule' })
write('rtl/b.sv', { 'module b; endmodule', 'module c; endmodule' })
write('rtl/c_bad.sv', { 'module bad(inout wire bus); endmodule' })
write('rtl/d_mixed.sv', { 'module bad(inout wire bus); endmodule', 'module good(input logic x); endmodule' })
write('rtl/e_invalid.sv', { 'module broken(' })
write('rtl/z.sv', { 'module z; endmodule' })
write('verible.filelist', { 'rtl/a.sv', 'rtl/b.sv', 'rtl/c_bad.sv', 'rtl/d_mixed.sv', 'rtl/e_invalid.sv', 'rtl/z.sv' })
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(buf, root .. '/new_tb.sv')
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '// target' })
local instance, parser = require('hdl.instance'), require('hdl.parser')
local state, actions = require('telescope.actions.state'), require('telescope.actions')
local telescope_state = require('telescope.state')
local real_request, real_notify = parser.request, vim.notify
local resolved, requests, notices, held = {}, {}, {}, {}
local hold = false
vim.notify = function(message) notices[#notices + 1] = tostring(message) end
parser.request = function(path, project, callback)
    requests[path] = (requests[path] or 0) + 1
    return real_request(path, project, function(value)
        local deliver = function() resolved[path] = true; callback(value) end
        -- Deliberately allow late delivery after cancellation to exercise picker guards.
        if hold then held[#held + 1] = { path = path, deliver = deliver } else deliver() end
    end)
end
local function wait(check, message)
    assert(vim.wait(6000, check, 10), message .. '\n' .. table.concat(notices, '\n'))
end
local function picker()
    local p
    wait(function()
        local ok, value = pcall(state.get_current_picker, vim.api.nvim_get_current_buf())
        if ok and value and value.manager and value.manager:num_results() > 0 then p = value; return true end
    end, 'picker missing')
    assert(p.cache_picker == false, 'one-shot picker must not retain an invalid insertion anchor')
    return p
end
local function preview_visible(p)
    local preview = telescope_state.get_status(p.prompt_bufnr).layout.preview
    return preview and preview.winid and vim.api.nvim_win_is_valid(preview.winid) or false
end
local function toggle(p, visible)
    require('telescope.actions.layout').toggle_preview(p.prompt_bufnr)
    wait(function() return preview_visible(p) == visible end, 'preview toggle did not finish')
    vim.wait(30) -- Telescope defers moving prompt/results after creating a preview.
end
local function select(p, label)
    local current = p:get_selection()
    local current_label = current and (current.value.label or current.value.name)
    if current_label ~= label then resolved[root .. '/' .. label] = nil end
    for i = 1, p.manager:num_results() do
        local item = p.manager:get_entry(i).value
        if (item.label or item.name) == label then p:set_selection(i - 1); return end
    end
    error('missing item: ' .. label)
end
local function ready(label)
    wait(function() return resolved[root .. '/' .. label] end, 'no parse without preview: ' .. label)
end
local function open(testbench)
    resolved = {}
    if testbench then instance.open_testbench() else instance.open() end
    return picker()
end
local function contents() return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local ok, err = xpcall(function()
    -- A narrow window hides the preview entirely. Enter must eventually insert.
    local p = open(true)
    assert(not preview_visible(p), 'fixture unexpectedly has a preview')
    local before = contents()
    actions.select_default(p.prompt_bufnr)
    assert(contents() == before, 'loading Enter inserted prematurely')
    ready('rtl/a.sv'); actions.select_default(p.prompt_bufnr)
    assert(contents():find('module a_tb;', 1, true), 'hidden-preview TB insertion failed')

    p = open(false); assert(not preview_visible(p)); ready('rtl/a.sv')
    actions.select_default(p.prompt_bufnr)
    assert(contents():find('a u_a', 1, true), 'hidden-preview instance insertion failed')

    -- Both the file and module stages must work with no preview window.
    p = open(true); select(p, 'rtl/b.sv'); ready('rtl/b.sv')
    actions.select_default(p.prompt_bufnr); p = picker()
    assert(p.prompt_title == 'Choose module' and not preview_visible(p))
    select(p, 'c'); actions.select_default(p.prompt_bufnr)
    assert(contents():find('module c_tb;', 1, true), 'hidden module picker failed')

    p = open(true); select(p, 'rtl/c_bad.sv'); ready('rtl/c_bad.sv')
    before = contents(); actions.select_default(p.prompt_bufnr)
    assert(contents() == before, 'unsupported TB inserted without preview')
    assert(notices[#notices]:find('inout', 1, true), 'unsupported TB stuck at Loading')
    actions.close(p.prompt_bufnr)

    p = open(true); select(p, 'rtl/d_mixed.sv'); ready('rtl/d_mixed.sv')
    actions.select_default(p.prompt_bufnr); p = picker(); select(p, 'bad')
    before = contents(); actions.select_default(p.prompt_bufnr)
    assert(contents() == before and notices[#notices]:find('inout', 1, true))
    select(p, 'good'); actions.select_default(p.prompt_bufnr)
    assert(contents():find('module good_tb;', 1, true), 'supported sibling was blocked')

    p = open(true); select(p, 'rtl/e_invalid.sv'); ready('rtl/e_invalid.sv')
    before = contents(); actions.select_default(p.prompt_bufnr)
    assert(contents() == before and notices[#notices]:find('Verible failed', 1, true), 'parse error was hidden by Loading')
    actions.close(p.prompt_bufnr)

    -- Prompt filtering drives selection too; zero matches must not use a stale entry.
    p = open(true); p:reset_prompt('no_such_file_xyz')
    wait(function() return p.manager:num_results() == 0 end, 'filter did not clear results')
    before = contents(); actions.select_default(p.prompt_bufnr)
    assert(contents() == before, 'empty result selection inserted stale module')
    p:reset_prompt('rtl/z.sv'); ready('rtl/z.sv')
    assert(p.manager:num_results() == 1, 'filter did not select one file')
    actions.select_default(p.prompt_bufnr)
    assert(contents():find('module z_tb;', 1, true), 'filtered hidden-preview insertion failed')

    -- Toggling preview is purely visual: no new parser request for the same entry.
    vim.o.columns = 160; vim.o.lines = 45
    p = open(true); ready('rtl/a.sv'); assert(preview_visible(p))
    local count = requests[root .. '/rtl/a.sv']
    toggle(p, false); toggle(p, true); vim.wait(200)
    assert(requests[root .. '/rtl/a.sv'] == count, 'toggle restarted parsing')
    toggle(p, false)
    select(p, 'rtl/z.sv'); ready('rtl/z.sv')
    toggle(p, true)
    wait(function()
        local preview = p.previewer.state.bufnr
        return preview and table.concat(vim.api.nvim_buf_get_lines(preview, 0, -1, false), '\n'):find('module z_tb;', 1, true)
    end, 'reshown preview did not paint the focused result')
    actions.close(p.prompt_bufnr)

    -- Resize while parsing, then deliver results out of order with preview hidden.
    hold = true; held = {}; p = open(true)
    wait(function() return #held == 1 end, 'first deferred result missing')
    vim.o.columns = 80; vim.o.lines = 24
    p:full_layout_update()
    wait(function() return not preview_visible(p) end, 'resize did not hide preview')
    select(p, 'rtl/z.sv')
    wait(function() return #held == 2 end, 'second deferred result missing')
    assert(held[1].path == root .. '/rtl/a.sv' and held[2].path == root .. '/rtl/z.sv')
    held[2].deliver(); held[1].deliver(); held = {}; hold = false
    before = contents(); actions.select_default(p.prompt_bufnr)
    -- Insertion is anchored in the middle of the buffer, so compare module counts.
    local _, old_count = before:gsub('module z_tb;', '')
    local _, new_count = contents():gsub('module z_tb;', '')
    assert(new_count == old_count + 1, 'late result replaced focused module')

    -- Closing a hidden picker cancels work and a late callback cannot insert/reopen it.
    hold = true; p = open(true)
    wait(function() return #held == 1 end, 'cancel fixture result missing')
    before = contents(); actions.close(p.prompt_bufnr)
    held[1].deliver(); held = {}; hold = false; vim.wait(200)
    assert(contents() == before, 'cancelled picker modified target')
    p = open(true); ready('rtl/a.sv'); actions.close(p.prompt_bufnr)
end, debug.traceback)
hold = false
for _, item in ipairs(held) do item.deliver() end
parser.request, vim.notify = real_request, real_notify
vim.fn.delete(root, 'rf')
if not ok then error(err) end
print('HDL picker: hidden preview, instance/TB, multi-module, errors, toggles, resize, stale/cancelled callbacks: PASS')
vim.cmd('qa!')
