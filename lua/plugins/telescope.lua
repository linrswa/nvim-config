local telescope = require("telescope")
local builtin = require("telescope.builtin")

telescope.setup({})

local map = vim.keymap.set
map("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
map("n", "<leader>fb", builtin.buffers, { desc = "Find buffers" })
map("n", "<leader>fc", builtin.current_buffer_fuzzy_find, { desc = "Find in current buffer" })
map("n", "<leader>fk", builtin.keymaps, { desc = "Find keymaps" })
map("n", "<leader>fh", builtin.help_tags, { desc = "Find help" })
map("n", "<leader>fd", builtin.diagnostics, { desc = "Workspace diagnostics" })
map("n", "<leader>fg", function()
    if vim.fn.executable("rg") == 1 then
        builtin.live_grep()
    else
        vim.notify("Telescope live grep requires ripgrep (rg).", vim.log.levels.WARN)
    end
end, { desc = "Live grep" })
