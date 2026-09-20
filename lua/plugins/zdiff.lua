local zdiff = require("zdiff")

zdiff.setup()

vim.keymap.set("n", "<leader>zd", function()
    zdiff.open()
end, { desc = "Zdiff uncommitted changes" })

vim.keymap.set("n", "<leader>zD", function()
    zdiff.open("main")
end, { desc = "Zdiff against main" })
