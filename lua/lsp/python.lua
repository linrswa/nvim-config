vim.lsp.config("basedpyright", {
    settings = {
        basedpyright = {
            analysis = {
                typeCheckingMode = "basic",
            },
        },
    },
})

vim.lsp.config("ruff", {})

vim.lsp.enable("basedpyright")
vim.lsp.enable("ruff")
