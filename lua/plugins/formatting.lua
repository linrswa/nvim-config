local conform = require("conform")

conform.setup({
    formatters_by_ft = {
        python = { "ruff_organize_imports", "ruff_format" },
        verilog = { "verible_verilog_format" },
        systemverilog = { "verible_verilog_format" },
    },
})

vim.keymap.set("n", "<leader>f", function()
    conform.format({ async = true, lsp_format = "fallback" })
end, { desc = "Format buffer" })
