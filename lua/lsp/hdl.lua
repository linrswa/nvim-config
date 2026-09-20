vim.lsp.config("verible", {
    filetypes = {
        "verilog",
        "systemverilog",
    },
})

vim.lsp.enable("verible")
