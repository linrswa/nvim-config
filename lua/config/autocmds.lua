vim.filetype.add({
    extension = {
        v = "verilog",
        sv = "systemverilog",
        svh = "systemverilog",
    },
})

local group = vim.api.nvim_create_augroup("UserConfig", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
    group = group,
    callback = function()
        vim.highlight.on_yank()
    end,
})

vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "python", "verilog", "systemverilog" },
    callback = function(args)
        pcall(vim.treesitter.start, args.buf)
    end,
})
