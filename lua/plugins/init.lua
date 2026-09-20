vim.pack.add({
    "https://github.com/mason-org/mason.nvim",
    "https://github.com/mason-org/mason-lspconfig.nvim",
    "https://github.com/neovim/nvim-lspconfig",
    "https://github.com/nvim-treesitter/nvim-treesitter",
    "https://github.com/rebelot/kanagawa.nvim",
    {
        src = "https://github.com/nvim-mini/mini.nvim",
        version = "ac5dffcc52b8378fbb15efeb0497a83e57a0b01c",
    },
    {
        src = "https://github.com/ThePrimeagen/harpoon",
        version = "87b1a3506211538f460786c23f98ec63ad9af4e5",
    },

    "https://github.com/nvim-lua/plenary.nvim",
    "https://github.com/nvim-telescope/telescope.nvim",
    "https://github.com/saghen/blink.lib",
    "https://github.com/Saghen/blink.cmp",
    "https://github.com/stevearc/conform.nvim",
    "https://github.com/kevinhwang91/nvim-hlslens",
    "https://github.com/rachartier/tiny-code-action.nvim",
    "https://github.com/abecodes/tabout.nvim",
    "https://github.com/Wansmer/treesj",
    "https://github.com/rachartier/tiny-cmdline.nvim",
    "https://github.com/artemave/workspace-diagnostics.nvim",
    "https://github.com/martindur/zdiff.nvim",
    "https://github.com/kdheepak/lazygit.nvim",
    {
        src = "https://github.com/christoomey/vim-tmux-navigator",
        version = "e41c431a0c7b7388ae7ba341f01a0d217eb3a432",
    },
})

require("plugins.mason")
require("plugins.treesitter")
require("plugins.telescope")
require("plugins.workspace-diagnostics")
require("plugins.tabout")
require("plugins.completion")
require("plugins.tiny-cmdline")
require("plugins.formatting")
require("plugins.treesj")
require("plugins.zdiff")
require("plugins.lazygit")
require("plugins.hlslens")
require("plugins.tiny-code-action")
require("plugins.mini")
require("plugins.harpoon")