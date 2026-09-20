local hlslens = require("hlslens")

hlslens.setup()

local map = vim.keymap.set
local opts = { silent = true }

map("n", "n", function()
    vim.cmd("normal! " .. vim.v.count1 .. "n")
    hlslens.start()
end, opts)

map("n", "N", function()
    vim.cmd("normal! " .. vim.v.count1 .. "N")
    hlslens.start()
end, opts)

for _, key in ipairs({ "*", "#", "g*", "g#" }) do
    map("n", key, key .. "<cmd>lua require('hlslens').start()<cr>", opts)
end

map("n", "<leader>l", "<cmd>nohlsearch<cr>", { silent = true, desc = "Clear search highlights" })
