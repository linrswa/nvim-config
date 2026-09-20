vim.g.lazygit_floating_window_use_plenary = 1
vim.g.lazygit_floating_window_scaling_factor = 0.9

vim.keymap.set("n", "<leader>gg", "<cmd>LazyGitCurrentFile<cr>", {
    silent = true,
    desc = "Open LazyGit for current project",
})
