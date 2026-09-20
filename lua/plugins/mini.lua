local map = vim.keymap.set

require("mini.icons").setup()
require("mini.ai").setup()
require("mini.jump").setup()
require("mini.surround").setup()
require("mini.files").setup()
require("mini.statusline").setup({
    content = {
        active = function()
            local mode, mode_hl = MiniStatusline.section_mode({ trunc_width = 120 })
            local filename = MiniStatusline.section_filename({ trunc_width = 140 })
            local location = MiniStatusline.section_location({ trunc_width = 75 })

            return MiniStatusline.combine_groups({
                { hl = mode_hl, strings = { mode } },
                "%<",
                { hl = "MiniStatuslineFilename", strings = { filename } },
                "%=",
                { hl = mode_hl, strings = { location } },
            })
        end,
    },
    use_icons = true,
})

map("n", "<leader>e", function()
    MiniFiles.open()
end, { desc = "Explore files" })
