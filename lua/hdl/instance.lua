-- Saved-source, conservative ANSI-module instantiation. No project files are written.
local M = {}
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
    local tb_error
    local parameters = find(header, "kFormalParameterList")
    for _, parameter in ipairs(children(parameters)) do
        if type(parameter) == "table" and parameter.tag ~= "," then
            if parameter.tag ~= "kParamDeclaration" then return reject("unsupported parameter declaration") end
            local first = leaves(parameter)[1]
            if first and (first.tag == "parameter" or first.tag == "localparam") then
                parameter_kind = first.tag
            end
            if parameter_kind == "localparam" then tb_error = "header localparams need module scope" end
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
                -- The TB copies constants into a new scope. Only this narrow
                -- subset is known to retain the original int semantics.
                local type_parts = {}
                for _, token in ipairs(leaves(param_type)) do
                    local value = text(source, token)
                    if value ~= pname then type_parts[#type_parts + 1] = value end
                end
                local kind = table.concat(type_parts, " ")
                local default = table.concat(parts)
                if (kind ~= "" and kind ~= "int") or not default:match("^%d+$")
                    or tonumber(default) > 2147483647 then
                    tb_error = "only untyped/int nonnegative decimal parameter defaults are supported in testbenches"
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
                local pname, description, direction
                if port.tag == "kPort" and #ts == 1 and ts[1].tag == "SymbolIdentifier" and inherited then
                    pname = text(source, ts[1])
                    description = inherited.description
                    direction = inherited.direction
                elseif port.tag == "kPortDeclaration" then
                    direction = ts[1] and text(source, ts[1])
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
                    inherited = { description = description, direction = direction }
                else
                    return reject("non-ANSI/complex port list")
                end
                if not identifier(pname) or seen[pname] then return reject("unsupported or duplicate port name") end
                seen[pname] = true
                ports[#ports + 1] = { name = pname, description = description, direction = direction }
            end
        end
    end
    return { name = name, source = path, ports = ports, parameters = parameter_values, tb_error = tb_error }
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

local function strip_leading_word(value, words)
    local word, rest = value:match("^(%S+)%s*(.*)$")
    if word and words[word] then return rest end
    return value
end

local function starts_with_type(value)
    local word = value:match("^(%S+)")
    return word == "logic" or word == "bit" or word == "byte" or word == "shortint"
        or word == "int" or word == "longint" or word == "integer" or word == "time"
end

local function port_local_type(port)
    local value = (port.description or ""):gsub("^%s+", ""):gsub("%s+$", "")
    value = strip_leading_word(value, { input = true, output = true, inout = true })
    value = strip_leading_word(value, { wire = true, tri = true, reg = true, var = true })
    if value == "" or value:match("^%[") or value:match("^signed%f[%W]") or value:match("^unsigned%f[%W]") then
        value = "logic" .. (value ~= "" and (" " .. value) or "")
    elseif not starts_with_type(value) then
        value = "logic " .. value
    end
    return value
end

local function aligned_signal_lines(ports, indent)
    local decls, width = {}, 0
    for _, port in ipairs(ports or {}) do
        local kind = port_local_type(port)
        decls[#decls + 1] = { kind = kind, name = port.name }
        width = math.max(width, #kind)
    end
    local lines = {}
    for _, decl in ipairs(decls) do
        lines[#lines + 1] = indent .. decl.kind .. string.rep(" ", width - #decl.kind + 1) .. decl.name .. ";"
    end
    return lines
end

function M.render_testbench(module, indent, unit)
    assert(not module.tb_error, module.tb_error)
    local known = { input = true, output = true }
    for word in pairs(simple_types) do known[word] = true end
    for _, parameter in ipairs(module.parameters or {}) do
        assert(not parameter.scoped, "testbench parameter requires module scope: " .. parameter.name)
        known[parameter.name] = true
    end
    for _, port in ipairs(module.ports or {}) do
        assert(port.direction ~= "inout", "inout testbench driving is not supported")
        assert(not (port.description or ""):find("[$'`:]%a"), "unsupported testbench dimension expression")
        for word in (port.description or ""):gmatch("[%a_$][%w_$]*") do
            assert(known[word], "testbench port type/dimension requires module scope: " .. word)
        end
    end
    indent, unit = indent or "", unit or "    "
    local lines = { indent .. "module " .. module.name .. "_tb;" }
    if module.parameters and #module.parameters > 0 then
        for _, parameter in ipairs(module.parameters) do
            if not parameter.scoped then
                lines[#lines + 1] = indent .. unit .. "localparam int " .. parameter.name .. " = " .. parameter.default .. ";"
            end
        end
        lines[#lines + 1] = ""
    end
    vim.list_extend(lines, aligned_signal_lines(module.ports, indent .. unit))
    lines[#lines + 1] = ""

    if module.parameters and #module.parameters > 0 then
        lines[#lines + 1] = indent .. unit .. module.name .. " #("
        for i, parameter in ipairs(module.parameters) do
            lines[#lines + 1] = indent .. unit .. unit .. "." .. parameter.name
                .. "(" .. (parameter.scoped and "" or parameter.name) .. ")"
                .. (i < #module.parameters and "," or "")
                .. (parameter.scoped and (" // Keep module default: " .. parameter.default) or "")
        end
        lines[#lines + 1] = indent .. unit .. ") dut ("
    else
        lines[#lines + 1] = indent .. unit .. module.name .. " dut ("
    end
    local max_port = 0
    for _, port in ipairs(module.ports or {}) do max_port = math.max(max_port, #port.name) end
    for i, port in ipairs(module.ports or {}) do
        lines[#lines + 1] = indent .. unit .. unit .. "." .. port.name
            .. string.rep(" ", max_port - #port.name) .. "(" .. port.name .. ")"
            .. (i < #module.ports and "," or "")
    end
    lines[#lines + 1] = indent .. unit .. ");"
    lines[#lines + 1] = ""

    local args = {}
    for _, port in ipairs(module.ports or {}) do
        local prefix = port.direction == "output" and "expected_" or "test_"
        args[#args + 1] = { kind = port_local_type(port), name = prefix .. port.name }
    end
    lines[#lines + 1] = indent .. unit .. "task automatic check("
    local max_kind = 0
    for _, arg in ipairs(args) do max_kind = math.max(max_kind, #arg.kind) end
    for i, arg in ipairs(args) do
        lines[#lines + 1] = indent .. unit .. unit .. "input " .. arg.kind
            .. string.rep(" ", max_kind - #arg.kind + 1) .. arg.name
            .. (i < #args and "," or "")
    end
    lines[#lines + 1] = indent .. unit .. ");"
    lines[#lines + 1] = indent .. unit .. unit .. "// TODO: drive inputs and check outputs"
    lines[#lines + 1] = indent .. unit .. "endtask"
    lines[#lines + 1] = ""

    lines[#lines + 1] = indent .. unit .. "initial begin"
    lines[#lines + 1] = indent .. unit .. unit .. "$dumpfile(\"" .. module.name .. ".vcd\");"
    lines[#lines + 1] = indent .. unit .. unit .. "$dumpvars(0, " .. module.name .. "_tb);"
    lines[#lines + 1] = ""
    lines[#lines + 1] = indent .. unit .. unit .. "// TODO: add test cases"
    lines[#lines + 1] = ""
    lines[#lines + 1] = indent .. unit .. unit .. "$display(\"PASS: " .. module.name .. "\");"
    lines[#lines + 1] = indent .. unit .. unit .. "$finish;"
    lines[#lines + 1] = indent .. unit .. "end"
    lines[#lines + 1] = ""
    lines[#lines + 1] = indent .. "endmodule"
    return lines
end

local function open_with(render, preview_title, prompt_title)
    require("hdl.picker").open(render, prompt_title or preview_title)
end

function M.open()
    open_with(M.render, "Instantiation (parameters + ports)", "HDL modules (saved sources)")
end

function M.open_testbench()
    open_with(M.render_testbench, "Testbench template", "HDL modules for testbench")
end

return M
