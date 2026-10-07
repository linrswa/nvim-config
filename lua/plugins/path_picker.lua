local M = {}
local uv = vim.uv
local ns = vim.api.nvim_create_namespace('find_paste_path')
local active = false
local ignored = {
    ['.git'] = true, ['.hg'] = true, ['.svn'] = true,
    node_modules = true, ['.venv'] = true, venv = true,
    __pycache__ = true, ['.cache'] = true,
    build = true, dist = true, target = true, obj_dir = true,
}
local function notify(message)
    vim.notify('Find/paste path: ' .. message, vim.log.levels.WARN)
end

function M.open()
    if active then notify('a picker is already open'); return end
    local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
    if not vim.bo[buf].modifiable then notify('buffer is not modifiable'); return end
    local root = vim.fs.root(buf, {
        '.git', '.hg', '.rtl-sources', 'CMakeLists.txt', 'pyproject.toml', 'package.json', 'Cargo.toml',
    }) or vim.fn.getcwd()
    root = vim.fs.normalize(root)
    local available, pickers = pcall(require, 'telescope.pickers')
    if not available then notify('Telescope is unavailable'); return end
    local actions = require('telescope.actions')
    local state = require('telescope.actions.state')
    local finders = require('telescope.finders')
    local cursor = vim.api.nvim_win_get_cursor(win)
    -- Insert BEFORE the character under the cursor (including a closing quote).
    local anchor = vim.api.nvim_buf_set_extmark(buf, ns, cursor[1] - 1, cursor[2], { right_gravity = false })
    local closed = false
    local function cleanup()
        if closed then return end
        closed = true
        active = false
        if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_del_extmark, buf, ns, anchor) end
    end
    local function finder(items)
        return finders.new_table({ results = items, entry_maker = function(item)
            return { value = item.path, ordinal = item.path,
                display = (item.directory and '[dir]  ' or '[file] ') .. item.path }
        end })
    end
    local picker = pickers.new({}, {
        prompt_title = 'Find / paste path — ' .. root,
        results_title = 'Scanning…',
        finder = finder({}),
        sorter = require('telescope.config').values.generic_sorter({}),
        previewer = false,
        -- A closed picker loses its insertion anchor; it must not be resumed.
        cache_picker = false,
        attach_mappings = function(prompt, map)
            vim.api.nvim_create_autocmd('BufWipeout', { buffer = prompt, once = true, callback = cleanup })
            local function paste()
                local entry = state.get_selected_entry()
                if not entry then return end
                if not vim.api.nvim_buf_is_loaded(buf) or not vim.bo[buf].modifiable
                    or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
                    notify('original buffer/window is unavailable'); actions.close(prompt); return
                end
                local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, anchor, {})
                if #pos == 0 then notify('insertion position is unavailable'); actions.close(prompt); return end
                local path = entry.value
                actions.close(prompt)
                vim.api.nvim_set_current_win(win)
                vim.api.nvim_buf_set_text(buf, pos[1], pos[2], pos[1], pos[2], { path })
                vim.api.nvim_win_set_cursor(win, { pos[1] + 1, pos[2] })
            end
            actions.select_default:replace(paste)
            for _, mode in ipairs({ 'i', 'n' }) do
                map(mode, '<Esc>', actions.close)
                -- This picker inserts text; split/tab shortcuts must not open paths.
                for _, key in ipairs({ '<C-x>', '<C-v>', '<C-t>' }) do map(mode, key, paste) end
            end
            return true
        end,
    })
    active = true
    local ok, err = pcall(function() picker:find() end)
    if not ok then cleanup(); notify(tostring(err)); return end

    -- Chunk traversal so typing/cancellation stays responsive without fd/rg dependencies.
    -- Dotfiles are included; symlinks are never followed and .gitignore is not applied.
    local queue, index, handle, directory = { '' }, 1, nil, nil
    local items, skipped = {}, 0
    local function step()
        if closed then return end
        for _ = 1, 100 do
            if handle then
                local name, kind = uv.fs_scandir_next(handle)
                if not name then
                    handle = nil
                else
                    local path = directory == '' and name or directory .. '/' .. name
                    if not kind or kind == 'unknown' then
                        local stat = uv.fs_lstat(root .. '/' .. path)
                        kind = stat and stat.type
                    end
                    -- Newlines cannot be pasted as a single path line.
                    if not name:find('[\r\n]') then
                        if kind == 'directory' and not ignored[name] then
                            items[#items + 1] = { path = path .. '/', directory = true }
                            queue[#queue + 1] = path
                        elseif kind == 'file' then
                            items[#items + 1] = { path = path }
                        end
                    end
                end
            elseif queue[index] then
                directory = queue[index]; index = index + 1
                handle = uv.fs_scandir(root .. '/' .. directory)
                if not handle then skipped = skipped + 1 end
            else
                table.sort(items, function(a, b) return a.path < b.path end)
                picker.results_title = 'Paths (relative to root)'
                picker:refresh(finder(items), { reset_prompt = false })
                if skipped > 0 then notify(skipped .. ' unreadable directories skipped') end
                return
            end
        end
        vim.schedule(step)
    end
    vim.schedule(step)
end
return M
