local conform = require("conform")

conform.setup({
    formatters = {
        verible = {
            prepend_args = { "--port_declarations_alignment=align" },
            range_args = function(_, ctx)
                return {
                    "--lines=" .. ctx.range.start[1] .. "-" .. ctx.range["end"][1],
                    "--stdin_name", "$FILENAME", "-",
                }
            end,
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

vim.keymap.set("x", "<leader>f", function()
    -- Conform infers ranges for v/V, but not for rectangular selections.
    local mode = vim.fn.mode()
    if mode ~= "v" and mode ~= "V" then
        vim.notify("Format selection: use v or V, not blockwise selection", vim.log.levels.WARN)
        return
    end
    local opts = { async = true, lsp_format = "fallback" }
    if vim.bo.filetype == "python" then
        -- Import organization is a whole-file operation, not a range formatter.
        opts.formatters = { "ruff_format" }
    end
    conform.format(opts)
end, { desc = "Format selection" })
