-- Keep the built-in rules, but align closing parentheses and endmodule.
-- Mask non-code text so parentheses/keywords in comments, strings and escaped
-- identifiers cannot be mistaken for matching delimiters.
local function code_lines(last)
    local lines = vim.api.nvim_buf_get_lines(0, 0, last, false)
    local block_comment, quoted = false, false
    for row, line in ipairs(lines) do
        local out, col = {}, 1
        while col <= #line do
            local char = line:sub(col, col)
            local two = line:sub(col, col + 1)
            local count, hide = 1, true
            if block_comment then
                if two == "*/" then
                    block_comment, count = false, 2
                end
            elseif quoted then
                if char == "\\" then
                    count = math.min(2, #line - col + 1)
                elseif char == '"' then
                    quoted = false
                end
            elseif two == "//" then
                count = #line - col + 1
            elseif two == "/*" then
                block_comment, count = true, 2
            elseif char == '"' then
                quoted = true
            elseif char == "\\" then
                -- SystemVerilog escaped identifiers end at whitespace.
                local stop = line:find("%s", col + 1) or (#line + 1)
                count = stop - col
            else
                hide = false
            end
            out[#out + 1] = hide and string.rep(" ", count) or char
            col = col + count
        end
        lines[row] = table.concat(out)
        -- Only a backslash-continued string can span source lines.
        if line:sub(-1) ~= "\\" then
            quoted = false
        end
    end
    return lines
end

_G.UserSystemVerilogIndent = function()
    local row = vim.v.lnum
    local line = vim.fn.getline(row)
    if not line:match("^%s*%)") and not line:match("^%s*endmodule%f[%W]") then
        return vim.fn.SystemVerilogIndent()
    end

    local code = code_lines(row)
    local open, close
    if code[row]:match("^%s*%)") then
        open, close = "(", ")"
    elseif code[row]:match("^%s*endmodule%f[%W]") then
        open, close = [[\<module\>]], [[\<endmodule\>]]
    else
        return vim.fn.SystemVerilogIndent()
    end

    local saved = vim.fn.getpos(".")
    -- Search strictly before the current line's closing delimiter.
    vim.fn.cursor(row, 1)
    local ok, pos = pcall(vim.fn.searchpairpos, open, "", close, "bnW", function()
        local text = code[vim.fn.line(".")] or ""
        local col = vim.fn.col(".")
        return text:sub(col, col):match("%S") == nil
    end)
    vim.fn.setpos(".", saved)
    if ok and pos[1] > 0 then
        return vim.fn.indent(pos[1])
    end
    return vim.fn.SystemVerilogIndent()
end

vim.bo.indentexpr = "v:lua.UserSystemVerilogIndent()"
-- The built-in script's b:undo_indent already resets indentexpr.
