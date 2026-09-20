require("config.options")
require("config.keymaps")
require("config.autocmds")

require("plugins")

require("lsp.python")
require("lsp.hdl")

require("kanagawa").setup({
    theme = "wave",
})
vim.cmd.colorscheme("kanagawa")
