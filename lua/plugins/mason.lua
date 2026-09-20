require("mason").setup({
    PATH = "prepend",
})

require("mason-lspconfig").setup({
    -- basedpyright is deliberately excluded: Mason installs it through npm.
    -- Add it here only after approving that npm installation.
    ensure_installed = {
        "ruff",
        "verible",
    },
    automatic_enable = false,
})
