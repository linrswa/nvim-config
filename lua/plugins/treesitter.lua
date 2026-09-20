local treesitter = require("nvim-treesitter")

-- The supported HDL grammar is SystemVerilog; it also parses Verilog files.
treesitter.install({
    "python",
    "systemverilog",
})

vim.treesitter.language.register("systemverilog", "verilog")
