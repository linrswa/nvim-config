vim.lsp.config("verible", {
    cmd = {
        "verible-verilog-ls",
        "--rules=parameter-name-style=localparam_style:CamelCase|ALL_CAPS",
    },
    filetypes = {
        "verilog",
        "systemverilog",
    },
})

vim.lsp.enable("verible")

local function scan(silent)
    local root = vim.fs.root(0, { ".git", "CMakeLists.txt" })
    if not root then
        vim.notify("找不到專案根目錄", vim.log.levels.ERROR)
        return
    end

    local excluded = {
        [".git"] = true,
        ["build"] = true,
        ["obj_dir"] = true,
    }

    local files = {}
    for path, kind in vim.fs.dir(root, {
        depth = math.huge,
        skip = function(name)
            return not excluded[vim.fs.basename(name)]
        end,
    }) do
        if kind == "file" and (path:match("%.sv$") or path:match("%.v$")) then
            table.insert(files, path)
        end
    end

    table.sort(files)

    local output = root .. "/verible.filelist"
    local ok, err = pcall(vim.fn.writefile, files, output)
    if not ok then
        vim.notify(tostring(err), vim.log.levels.ERROR)
        return
    end

    if not silent then
        vim.notify(("已更新 %s：%d 個檔案"):format(output, #files))
    end
    return root
end

vim.api.nvim_create_user_command("VeribleScan", function(opts)
    scan(opts.bang)
end, {
    desc = "掃描 RTL 並重新產生 verible.filelist（! 靜默）",
    bang = true,
    force = true,
})

local lint = require("lsp.verilator_lint")
local group = vim.api.nvim_create_augroup("HdlLintOnSave", { clear = true })
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = group,
    pattern = { "*.sv", "*.v", "*.svh", "*.vh" },
    callback = function(args)
        local root = vim.fs.root(args.buf, { ".git", "CMakeLists.txt" })
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
        local root = scan(true)
        if root then
            lint.run(root, args.buf)
        end
    end,
    desc = "更新 filelist 並執行專案級 Verilator lint",
})

vim.api.nvim_create_user_command("VerilatorLint", function()
    local root = scan(true)
    if root then
        lint.run(root, vim.api.nvim_get_current_buf())
    end
end, { desc = "掃描 RTL 並執行 Verilator lint", force = true })
