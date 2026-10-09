vim.lsp.config("verible", {
    cmd = {
        "verible-verilog-ls",
        "--rules=parameter-name-style=localparam_style:CamelCase|ALL_CAPS",
    },
    filetypes = {
        "verilog",
        "systemverilog",
    },
    on_attach = function(client)
        -- This Verible version answers hover requests but advertises hoverProvider=false.
        client.server_capabilities.hoverProvider = true
    end,
})

vim.lsp.enable("verible")

vim.api.nvim_create_user_command("RTLInstance", function()
    require("hdl.instance").open()
end, {
    desc = "預覽並插入專案 module 的 instance 模板（使用已儲存檔案）",
    force = true,
})

vim.api.nvim_create_user_command("RTLTestbench", function()
    require("hdl.instance").open_testbench()
end, {
    desc = "預覽並插入專案 module 的 testbench 模板（使用已儲存檔案）",
    force = true,
})

vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("HdlInstanceKeymaps", { clear = true }),
    pattern = { "verilog", "systemverilog" },
    callback = function(args)
        vim.keymap.set("n", "<leader>fi", "<cmd>RTLInstance<CR>", {
            buffer = args.buf,
            desc = "Find RTL instance",
        })
    end,
})

local sources = require("hdl.sources")
local lint = require("lsp.verilator_lint")
local function hdl_buffer(buf)
    if not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].buftype ~= "" then return false end
    local name = vim.api.nvim_buf_get_name(buf)
    return name:match("%.svh?$") or name:match("%.vh?$")
end
local function request(buf, refresh)
    if not hdl_buffer(buf) then return end
    local root = sources.root(buf)
    if not root then return end
    local scope = vim.uv.fs_stat(root .. "/.rtl-sources")
    local list = vim.uv.fs_stat(root .. "/verible.filelist")
    if scope and (refresh or not list) then
        lint.refresh(root, buf, true)
    elseif list then
        lint.run(root, buf)
    end
end
vim.api.nvim_create_user_command("RTLSources", sources.open, { force = true })
vim.api.nvim_create_user_command("VeribleScan", function(opts)
    local buf = vim.api.nvim_get_current_buf()
    lint.refresh(sources.root(), hdl_buffer(buf) and buf or nil, opts.bang)
end, { bang = true, force = true })
vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("HdlSourceScope", { clear = true }),
    pattern = ".rtl-sources",
    callback = function(args)
        lint.refresh(vim.fs.dirname(vim.api.nvim_buf_get_name(args.buf)), nil, true)
    end,
})

local group = vim.api.nvim_create_augroup("HdlLintOnSave", { clear = true })
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufEnter", "BufFilePost" }, {
    group = group,
    pattern = { "*.sv", "*.v", "*.svh", "*.vh" },
    callback = function(args) request(args.buf, true) end,
    desc = "進入或重新命名 HDL buffer 時刷新 scope，再執行 lint",
})
vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave" }, {
    group = group,
    callback = function()
        local buf = vim.api.nvim_get_current_buf()
        if hdl_buffer(buf) then request(buf, true); return end
        -- Also refresh when returning to a terminal or another file in the project.
        local root = sources.root(buf) or sources.root(vim.fn.getcwd())
        if root and vim.uv.fs_stat(root .. "/.rtl-sources") then lint.refresh(root, nil, true) end
    end,
    desc = "回到編輯器／離開 terminal 時刷新目前專案",
})
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = group,
    pattern = { "*.sv", "*.v", "*.svh", "*.vh" },
    callback = function(args) request(args.buf, false) end,
    desc = "一般打字沿用 filelist；pending refresh 完成後才 lint",
})
vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = { "*.sv", "*.v", "*.svh", "*.vh" },
    callback = function(args)
        if not hdl_buffer(args.buf) then return end
        require("hdl.parser").invalidate(vim.api.nvim_buf_get_name(args.buf))
        request(args.buf, true)
    end,
    desc = "儲存 HDL 後刷新 scope，再執行 lint",
})

vim.api.nvim_create_user_command("VerilatorLint", function()
    local buf = vim.api.nvim_get_current_buf()
    local root = sources.root()
    if root then
        if vim.uv.fs_stat(root .. "/.rtl-sources") then
            lint.refresh(root, hdl_buffer(buf) and buf or nil, true)
        elseif hdl_buffer(buf) then
            lint.run(root, buf)
        end
    end
end, { desc = "刷新 RTL scope 後執行 Verilator lint", force = true })
