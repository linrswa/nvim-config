local conform = require("conform")

conform.setup({
    formatters = {
        verible = {
            prepend_args = { "--port_declarations_alignment=align" },
        },
    },
    formatters_by_ft = {
        python = { "ruff_organize_imports", "ruff_format" },
        verilog = { "verible" },
        systemverilog = { "verible" },
    },
})

vim.keymap.set("n", "<leader>f", function()
    conform.format({ async = true, lsp_format = "fallback" })
end, { desc = "Format buffer" })
