local tiny_code_action = require("tiny-code-action")

tiny_code_action.setup({
    backend = "vim",
    picker = "telescope",
})

vim.keymap.set({ "n", "x" }, "<leader>ca", function()
    tiny_code_action.code_action()
end, { silent = true, desc = "Code action" })
