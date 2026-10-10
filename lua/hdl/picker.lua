local M = {}
local active = false
local ns = vim.api.nvim_create_namespace('hdl.picker')
local function notify(s) vim.notify('HDL: ' .. tostring(s), vim.log.levels.WARN) end
function M.open(render, title)
    if active then notify('a picker is already open'); return end
    local root = require('hdl.sources').root()
    if not root then notify('cannot find project root'); return end
    local ok, lines = pcall(vim.fn.readfile, root .. '/verible.filelist')
    if not ok then notify('Run :RTLSources and save a source scope first'); return end
    local files, seen = {}, {}
    for _, line in ipairs(lines) do
        line = vim.trim(line)
        if line ~= '' and not line:match('^#') and not line:match('^//') then
            if line:match('^[-+]') or line:find('[$"]') then notify('Expected plain filelist paths'); return end
            local path = vim.fs.normalize(line:sub(1, 1) == '/' and line or root .. '/' .. line)
            if not seen[path] then files[#files + 1] = { path = path, label = line }; seen[path] = true end
        end
    end
    if #files == 0 then notify('filelist is empty'); return end
    local available, pickers = pcall(require, 'telescope.pickers')
    if not available then notify(pickers); return end
    table.sort(files, function(a, b) return a.path < b.path end)
    local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
    if not vim.bo[buf].modifiable then notify('target is not modifiable'); return end
    local anchor = vim.api.nvim_buf_set_extmark(buf, ns, vim.api.nvim_win_get_cursor(win)[1] - 1, 0, { right_gravity = false })
    active = true
    local closed, generation, cancel = false, 0, nil
    local function stop() generation = generation + 1; if cancel then cancel(); cancel = nil end end
    local function cleanup()
        if closed then return end
        closed = true; active = false; stop()
        if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_del_extmark, buf, ns, anchor) end
    end
    local function insert(module)
        if not vim.api.nvim_buf_is_loaded(buf) or not vim.bo[buf].modifiable then notify('target unavailable'); return end
        local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, anchor, {})
        if #pos == 0 then notify('insertion anchor unavailable'); return end
        local line = vim.api.nvim_buf_get_lines(buf, pos[1], pos[1] + 1, false)[1] or ''
        local width = vim.bo[buf].shiftwidth; if width == 0 then width = vim.bo[buf].tabstop end
        local rendered, result = pcall(render, module, line:match('^%s*'), vim.bo[buf].expandtab and string.rep(' ', width) or '\t')
        if not rendered then notify(result); return end
        vim.api.nvim_buf_set_lines(buf, pos[1] + 1, pos[1] + 1, false, result)
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
            vim.api.nvim_set_current_win(win); vim.api.nvim_win_set_cursor(win, { pos[1] + 2, 0 })
        end
    end
    local actions, state = require('telescope.actions'), require('telescope.actions.state')
    local show
    show = function(items, modules)
        local transferring = false
        local focused, result, content, preview, preview_item
        local function paint()
            if not closed and not transferring and preview and preview_item == focused
                and vim.api.nvim_buf_is_valid(preview) then
                vim.api.nvim_buf_set_lines(preview, 0, -1, false, content or {})
                vim.bo[preview].filetype = 'systemverilog'
            end
        end
        -- Parsing belongs to selection state, not to the optional preview window.
        local function focus(entry)
            if closed or transferring then return end
            local item = entry and entry.value
            if focused == item then paint(); return end
            stop(); local ticket = generation
            focused, result, content = item, nil, item and { '// Loading…' } or {}
            paint()
            if not item then return end
            local function ready(value)
                if closed or transferring or ticket ~= generation then return end
                result = value
                if value.error then
                    content = vim.split(value.error, '\n', { plain = true }); paint(); return
                end
                content = {}
                for _, warning in ipairs(value.warnings or {}) do
                    content[#content + 1] = '// Warning: ' .. warning
                end
                for _, module in ipairs(value.modules) do
                    local good, rendered = pcall(render, module)
                    if not good then
                        if #value.modules == 1 then result = { error = tostring(rendered) } end
                        content[#content + 1] = '// ' .. module.name .. ': unavailable'
                        vim.list_extend(content, vim.split(tostring(rendered), '\n'))
                    else
                        vim.list_extend(content, rendered)
                    end
                    content[#content + 1] = ''
                end
                paint()
            end
            if modules then ready({ modules = { item } }); return end
            vim.defer_fn(function()
                if closed or transferring or ticket ~= generation then return end
                cancel = require('hdl.parser').request(item.path, root, ready)
            end, 120)
        end
        local picker = pickers.new({}, {
            prompt_title = modules and 'Choose module' or title,
            cache_picker = false, -- Closing destroys this one-shot insertion anchor.
            finder = require('telescope.finders').new_table({ results = items, entry_maker = function(item)
                local label = modules and item.name or item.label
                return { value = item, display = label, ordinal = label }
            end }),
            sorter = require('telescope.config').values.generic_sorter({}),
            previewer = require('telescope.previewers').new_buffer_previewer({ title = title,
                define_preview = function(self, entry)
                    preview, preview_item = self.state.bufnr, entry.value
                    paint()
                end,
            }),
            attach_mappings = function(prompt, map)
                map('i', '<Esc>', actions.close)
                map('n', '<Esc>', actions.close)
                vim.api.nvim_create_autocmd('BufWipeout', { buffer = prompt, once = true, callback = function()
                    if not transferring then cleanup() end
                end })
                actions.select_default:replace(function()
                    local entry = state.get_selected_entry()
                    focus(entry) -- Defensive fallback if selection changed without set_selection.
                    if not entry then return end
                    if not result then notify('Loading…'); return end
                    if result.error then notify(result.error); return end
                    if #result.modules > 1 then
                        local choices = result.modules
                        transferring = true; stop(); actions.close(prompt)
                        vim.schedule(function()
                            if closed then return end
                            local good, err = pcall(show, choices, true)
                            if not good then cleanup(); notify(err) end
                        end)
                    else
                        local module = result.modules[1]
                        transferring = true; stop(); actions.close(prompt)
                        insert(module); cleanup()
                    end
                end)
                return true
            end,
        })
        -- Telescope calls set_selection for navigation and filtered results even
        -- when preview_cutoff hides the preview. Keep this hook picker-local.
        local set_selection = picker.set_selection
        picker.set_selection = function(self, row)
            set_selection(self, row)
            focus(self:get_selection())
        end
        picker:find()
    end
    local good, err = pcall(show, files, false)
    if not good then cleanup(); notify(err) end
end
return M
