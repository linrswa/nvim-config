-- Saved-source, conservative ANSI-module instantiation. No project files are written.
local M = {}
local ns = vim.api.nvim_create_namespace("hdl.instance")
local active = false

local function notify(message, level)
    vim.notify("HDL instance: " .. message, level or vim.log.levels.ERROR)
end

local function children(node)
    return type(node) == "table" and node.children or {}
end

local function find(node, tag)
    if type(node) ~= "table" then return end
    if node.tag == tag then return node end
    for _, child in ipairs(children(node)) do
        local result = find(child, tag)
        if result then return result end
    end
end

local function leaves(node, result)
    result = result or {}
    if type(node) ~= "table" then return result end
    if node.start then result[#result + 1] = node end
    for _, child in ipairs(children(node)) do leaves(child, result) end
    return result
end

local function text(source, token)
    return source:sub(token.start + 1, token["end"])
end

local function identifier(value)
    return value:match("^[%a_][%w_$]*$") ~= nil
end

local simple_types = {}
for word in ("wire tri logic reg bit byte shortint int longint integer time signed unsigned var"):gmatch("%S+") do
    simple_types[word] = true
end

local function module_info(node, source, path)
    local header = find(node, "kModuleHeader")
    if not header then return nil, "missing module header" end
    local name
    for _, child in ipairs(children(header)) do
        if type(child) == "table" and child.tag == "SymbolIdentifier" then
            name = text(source, child)
            break
        end
    end
    if not name or not identifier(name) then return nil, "unsupported module name" end
    local function reject(reason) return nil, name .. ": " .. reason end
    local tokens = leaves(header)
    local header_text = source:sub(tokens[1].start + 1, tokens[#tokens]["end"])
    if header_text:find("`", 1, true) then return reject("macros/directives in header") end
    local parameter_values, parameter_kind = {}, "parameter"
    local parameters = find(header, "kFormalParameterList")
    for _, parameter in ipairs(children(parameters)) do
        if type(parameter) == "table" and parameter.tag ~= "," then
            if parameter.tag ~= "kParamDeclaration" then return reject("unsupported parameter declaration") end
            local first = leaves(parameter)[1]
            if first and (first.tag == "parameter" or first.tag == "localparam") then
                parameter_kind = first.tag
            end
            if parameter_kind ~= "localparam" then
                local assignment = find(parameter, "kTrailingAssign")
                local param_type = find(parameter, "kParamType")
                if not assignment or not param_type then
                    return reject("required or type parameters are not supported")
                end
                local pname
                for _, child in ipairs(children(param_type)) do
                    if type(child) == "table" then
                        if child.tag == "SymbolIdentifier" then pname = text(source, child)
                        elseif child.tag == "kUnqualifiedId" then
                            local ids = leaves(child)
                            if #ids == 1 then pname = text(source, ids[1]) end
                        elseif child.tag == "kUnpackedDimensions" and #leaves(child) > 0 then
                            return reject("unpacked parameter arrays are not supported")
                        end
                    end
                end
                if not pname or not identifier(pname) then return reject("unsupported parameter name") end
                local expression = find(assignment, "kExpression")
                local ts, parts, scoped = leaves(expression), {}, false
                if #ts == 0 then return reject("unsupported parameter default") end
                for i, token in ipairs(ts) do
                    -- Preserve token spelling/adjacency, but discard comments between tokens.
                    if i > 1 and token.start > ts[i - 1]["end"] then parts[#parts + 1] = " " end
                    local value = text(source, token)
                    if value:find("[\r\n]") then return reject("multiline parameter literals are not supported") end
                    parts[#parts + 1] = value
                    if token.tag == "SymbolIdentifier" or token.tag == "EscapedIdentifier" then scoped = true end
                end
                parameter_values[#parameter_values + 1] = {
                    name = pname, default = table.concat(parts), scoped = scoped,
                }
            end
        end
    end
    local ports, inherited, seen = {}, nil, {}
    local list = find(header, "kPortDeclarationList")
    -- Verible uses kPortList for some non-ANSI forms.
    if not list and find(header, "kPortList") then return reject("non-ANSI ports") end
    if list then
        for _, port in ipairs(children(list)) do
            if type(port) == "table" and port.tag ~= "," then
                local ts = leaves(port)
                local pname, description
                if port.tag == "kPort" and #ts == 1 and ts[1].tag == "SymbolIdentifier" and inherited then
                    pname, description = text(source, ts[1]), inherited
                elseif port.tag == "kPortDeclaration" then
                    local direction = ts[1] and text(source, ts[1])
                    if direction ~= "input" and direction ~= "output" and direction ~= "inout" then
                        return reject("interface/implicit-direction ports are not supported")
                    end
                    local id
                    for _, child in ipairs(children(port)) do
                        if type(child) == "table" and child.tag == "kUnqualifiedId" then id = child end
                    end
                    local ids = leaves(id)
                    if #ids ~= 1 or ids[1].tag ~= "SymbolIdentifier" or ts[#ts] ~= ids[1] then
                        return reject("complex ports, unpacked dimensions or port defaults are not supported")
                    end
                    -- Only built-in scalar/net types and arbitrary packed dimension expressions.
                    local depth = 0
                    for i = 2, #ts - 1 do
                        local value = text(source, ts[i])
                        if value == "[" then depth = depth + 1
                        elseif value == "]" then depth = depth - 1
                        elseif depth == 0 and not simple_types[value] then
                            return reject("unsupported port type: " .. value)
                        end
                        if depth < 0 then return reject("invalid packed dimensions") end
                    end
                    if depth ~= 0 then return reject("invalid packed dimensions") end
                    pname = text(source, ids[1])
                    -- Build comments from CST leaves (source comments cannot leak into generated HDL).
                    local parts = {}
                    for i = 1, #ts - 1 do parts[#parts + 1] = text(source, ts[i]):gsub("%s+", " ") end
                    description = table.concat(parts, " ")
                    inherited = description
                else
                    return reject("non-ANSI/complex port list")
                end
                if not identifier(pname) or seen[pname] then return reject("unsupported or duplicate port name") end
                seen[pname] = true
                ports[#ports + 1] = { name = pname, description = description }
            end
        end
    end
    return { name = name, source = path, ports = ports, parameters = parameter_values }
end

-- Public pure helpers: parse(source, decoded Verible tree/file record, path) -> modules, warnings.
-- A syntax-error record is rejected as a whole; callers must also check process exit status.
function M.parse(source, tree, path)
    path = path or "<source>"
    if tree.errors and #tree.errors > 0 then return {}, { path .. ": syntax errors" } end
    tree = tree.tree or tree
    -- Conditional preprocessing can change the module inventory even outside headers.
    -- Conservatively reject these files rather than advertise an unverified interface.
    if source:match("`ifdef%f[%W]") or source:match("`ifndef%f[%W]")
        or source:match("`elsif%f[%W]") or source:match("`include%f[%W]") then
        return {}, { path .. ": conditional preprocessing/includes are not supported" }
    end
    local modules, warnings = {}, {}
    local function visit(node)
        if type(node) ~= "table" then return end
        if node.tag == "kModuleDeclaration" then
            local item, err = module_info(node, source, path)
            if item then modules[#modules + 1] = item
            else warnings[#warnings + 1] = path .. ": " .. err end
            return
        end
        for _, child in ipairs(children(node)) do visit(child) end
    end
    visit(tree)
    return modules, warnings
end

-- Empty named parameter assignments retain defaults in the instantiated module's scope.
function M.render(module, indent, unit)
    indent, unit = indent or "", unit or "    "
    local lines = {}
    if module.parameters and #module.parameters > 0 then
        lines[#lines + 1] = indent .. module.name .. " #("
        for i, parameter in ipairs(module.parameters) do
            lines[#lines + 1] = indent .. unit .. "." .. parameter.name
                .. "(" .. (parameter.scoped and "" or parameter.default) .. ")"
                .. (i < #module.parameters and "," or "")
                .. (parameter.scoped and (" // Keep module default: " .. parameter.default) or "")
        end
        lines[#lines + 1] = indent .. ") u_" .. module.name .. " ("
    else
        lines[#lines + 1] = indent .. module.name .. " u_" .. module.name .. " ("
    end
    for i, port in ipairs(module.ports) do
        lines[#lines + 1] = indent .. unit .. "." .. port.name .. "()"
            .. (i < #module.ports and "," or "") .. " // " .. port.description
    end
    lines[#lines + 1] = indent .. ");"
    return lines
end

function M.open()
    if active then notify("an instance search/picker is already open", vim.log.levels.WARN); return end
    local ok, pickers = pcall(require, "telescope.pickers")
    if not ok then notify("Telescope is unavailable: " .. tostring(pickers)); return end
    local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
    if not vim.bo[buf].modifiable then notify("target buffer is not modifiable"); return end
    local root = vim.fs.root(buf, { ".git", "CMakeLists.txt" })
    if not root then notify("cannot find project root (.git or CMakeLists.txt)"); return end
    local listpath = root .. "/verible.filelist"
    local read_ok, lines = pcall(vim.fn.readfile, listpath)
    if not read_ok then notify("cannot read " .. listpath .. ": " .. tostring(lines)); return end
    local binary = "verible-verilog-syntax"
    if vim.fn.executable(binary) ~= 1 then binary = vim.fn.expand("~/.local/share/nvim/mason/bin/" .. binary) end
    if vim.fn.executable(binary) ~= 1 then notify("verible-verilog-syntax is not executable"); return end
    local files, seen = {}, {}
    for number, line in ipairs(lines) do
        line = vim.trim(line)
        if line ~= "" and not line:match("^#") and not line:match("^//") then
            if line:match("^[-+]") or line:find("$", 1, true) or line:find('"', 1, true) then
                notify(("%s:%d: expected a plain source path (filelist options/expansion unsupported)"):format(listpath, number))
                return
            end
            local path = vim.fs.normalize(line:sub(1, 1) == "/" and line or root .. "/" .. line)
            if not seen[path] then files[#files + 1], seen[path] = path, true end
        end
    end
    if #files == 0 then notify("verible.filelist contains no source paths"); return end
    local row = vim.api.nvim_win_get_cursor(win)[1] - 1
    local anchor = vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { right_gravity = false })
    local cleaned = false
    active = true
    local function cleanup()
        if cleaned then return end
        cleaned = true
        active = false
        if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_del_extmark, buf, ns, anchor) end
    end
    local modules, warnings = {}, {}
    local function show()
        if #warnings > 0 then notify(table.concat(warnings, "\n"), vim.log.levels.WARN) end
        if not vim.api.nvim_buf_is_loaded(buf) then cleanup(); return end
        if #modules == 0 then cleanup(); notify("no supported modules found in saved sources"); return end
        table.sort(modules, function(a, b) return a.name .. a.source < b.name .. b.source end)
        local actions = require("telescope.actions")
        local state = require("telescope.actions.state")
        local picker = pickers.new({}, {
            prompt_title = "HDL modules (saved sources)",
            finder = require("telescope.finders").new_table({
                results = modules,
                entry_maker = function(item)
                    local relative = item.source:sub(1, #root + 1) == root .. "/" and item.source:sub(#root + 2) or item.source
                    local label = item.name .. "  —  " .. relative
                    return { value = item, display = label, ordinal = label }
                end,
            }),
            sorter = require("telescope.config").values.generic_sorter({}),
            previewer = require("telescope.previewers").new_buffer_previewer({
                title = "Instantiation (parameters + ports)",
                define_preview = function(self, entry)
                    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, M.render(entry.value))
                    vim.bo[self.state.bufnr].filetype = "systemverilog"
                end,
            }),
            attach_mappings = function(prompt, map)
                map("i", "<Esc>", actions.close)
                map("n", "<Esc>", actions.close)
                vim.api.nvim_create_autocmd("BufWipeout", { buffer = prompt, once = true, callback = cleanup })
                actions.select_default:replace(function()
                    local entry = state.get_selected_entry()
                    local pos = vim.api.nvim_buf_is_loaded(buf)
                        and vim.api.nvim_buf_get_extmark_by_id(buf, ns, anchor, {}) or {}
                    actions.close(prompt)
                    cleanup()
                    if not entry then return end
                    if #pos == 0 or not vim.api.nvim_buf_is_loaded(buf) or not vim.bo[buf].modifiable then
                        notify("original insertion buffer/anchor is no longer available"); return
                    end
                    local line = vim.api.nvim_buf_get_lines(buf, pos[1], pos[1] + 1, false)[1] or ""
                    local width = vim.bo[buf].shiftwidth
                    if width == 0 then width = vim.bo[buf].tabstop end
                    local unit = vim.bo[buf].expandtab and string.rep(" ", width) or "\t"
                    local rendered = M.render(entry.value, line:match("^%s*") or "", unit)
                    local inserted, err = pcall(vim.api.nvim_buf_set_lines, buf, pos[1] + 1, pos[1] + 1, false, rendered)
                    if not inserted then notify("insertion failed: " .. tostring(err)); return end
                    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
                        vim.api.nvim_set_current_win(win)
                        vim.api.nvim_win_set_cursor(win, { pos[1] + 2, 0 })
                    end
                end)
                return true
            end,
        })
        picker:find()
    end
    -- Sequential asynchronous subprocesses bound resource usage for large filelists.
    local index = 0
    local function next_file()
        if not vim.api.nvim_buf_is_loaded(buf) then cleanup(); return end
        index = index + 1
        local path = files[index]
        if not path then
            local shown, err = pcall(show)
            if not shown then cleanup(); notify("picker failed: " .. tostring(err)) end
            return
        end
        local loaded, content = pcall(vim.fn.readfile, path, "b")
        if not loaded then
            warnings[#warnings + 1] = path .. ": cannot read: " .. tostring(content)
            vim.schedule(next_file)
            return
        end
        local source = table.concat(content, "\n")
        local started, err = pcall(vim.system, { binary, "--export_json", "--printtree", "-" },
            { stdin = source, text = true, cwd = root, timeout = 15000 }, function(result)
                vim.schedule(function()
                    if result.code ~= 0 then
                        warnings[#warnings + 1] = path .. ": parser failed (exit " .. result.code .. "): "
                            .. ((result.stderr ~= "" and result.stderr) or result.stdout or ""):sub(1, 800)
                    else
                        local decoded, data = pcall(vim.json.decode, result.stdout)
                        if not decoded or not data["-"] or not data["-"].tree then
                            warnings[#warnings + 1] = path .. ": invalid/missing Verible JSON tree"
                        else
                            local parsed, items, notes = pcall(M.parse, source, data["-"], path)
                            if not parsed then warnings[#warnings + 1] = path .. ": CST parsing failed: " .. tostring(items)
                            else
                                vim.list_extend(modules, items)
                                vim.list_extend(warnings, notes)
                            end
                        end
                    end
                    next_file()
                end)
            end)
        if not started then cleanup(); notify("could not start parser: " .. tostring(err)) end
    end
    notify("reading " .. #files .. " saved source(s)…", vim.log.levels.INFO)
    next_file()
end

return M
