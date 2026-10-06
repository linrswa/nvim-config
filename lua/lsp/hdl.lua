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
vim.api.nvim_create_user_command("RTLSources", sources.open, { force = true })
vim.api.nvim_create_user_command("VeribleScan", function(opts)
    sources.scan(sources.root(), opts.bang)
end, { bang = true, force = true })
vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("HdlSourceScope", { clear = true }),
    pattern = ".hdl-sources",
    callback = function(args) sources.scan(vim.fs.dirname(vim.api.nvim_buf_get_name(args.buf)), true) end,
})

local lint = require("lsp.verilator_lint")
local group = vim.api.nvim_create_augroup("HdlLintOnSave", { clear = true })
vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    pattern = { "*.sv", "*.v", "*.svh", "*.vh" },
    callback = function(args)
        -- Opening real sources should lint too; preview/scratch buffers must not.
        if not vim.api.nvim_buf_is_loaded(args.buf) or vim.bo[args.buf].buftype ~= "" then return end
        local root = sources.root(args.buf)
        if root and vim.uv.fs_stat(root .. "/verible.filelist") then
            lint.run(root, args.buf)
        end
    end,
    desc = "開啟 HDL 檔案時以既有 filelist 執行 debounced Verilator lint",
})
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = group,
    pattern = { "*.sv", "*.v", "*.svh", "*.vh" },
    callback = function(args)
        local root = sources.root(args.buf)
        -- Live edits only read the existing list; never scan/write project files.
        if root and vim.uv.fs_stat(root .. "/verible.filelist") then
            lint.run(root, args.buf)
        end
    end,
    desc = "以未儲存的 buffer 執行 debounced Verilator lint",
})
vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = { "*.sv", "*.v", "*.svh", "*.vh" },
    callback = function(args)
        require("hdl.parser").invalidate(vim.api.nvim_buf_get_name(args.buf))
        local root = sources.root(args.buf)
        if root and vim.uv.fs_stat(root .. "/verible.filelist") then
            lint.run(root, args.buf)
        end
    end,
    desc = "以既有 filelist 執行專案級 Verilator lint",
})

vim.api.nvim_create_user_command("VerilatorLint", function()
    local root = sources.root()
    if root then
        lint.run(root, vim.api.nvim_get_current_buf())
    end
end, { desc = "以既有 filelist 執行 Verilator lint", force = true })
