local harpoon = require("harpoon")

harpoon:setup()

local map = vim.keymap.set

map("n", "<leader>a", function()
    harpoon:list():add()
end, { desc = "Harpoon add file" })

map("n", "<leader>h", function()
    harpoon.ui:toggle_quick_menu(harpoon:list())
end, { desc = "Harpoon menu" })

map("n", "<leader>1", function()
    harpoon:list():select(1)
end, { desc = "Harpoon file 1" })

map("n", "<leader>2", function()
    harpoon:list():select(2)
end, { desc = "Harpoon file 2" })

map("n", "<leader>3", function()
    harpoon:list():select(3)
end, { desc = "Harpoon file 3" })

map("n", "<leader>4", function()
    harpoon:list():select(4)
end, { desc = "Harpoon file 4" })

map("n", "<C-S-P>", function()
    harpoon:list():prev()
end, { desc = "Harpoon previous file" })

map("n", "<C-S-N>", function()
    harpoon:list():next()
end, { desc = "Harpoon next file" })
