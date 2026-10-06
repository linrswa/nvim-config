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
            local recording = vim.fn.reg_recording()
            local mode_section_hl = mode_hl
            if recording ~= "" then
                mode = mode .. " · @" .. recording
                mode_section_hl = "MiniStatuslineModeReplace"
            end
            local filename = MiniStatusline.section_filename({ trunc_width = 140 })
            local location = MiniStatusline.section_location({ trunc_width = 75 })

            return MiniStatusline.combine_groups({
                { hl = mode_section_hl, strings = { mode } },
                "%<",
                { hl = "MiniStatuslineFilename", strings = { filename } },
                "%=",
                { hl = mode_hl, strings = { location } },
            })
        end,
    },
    use_icons = true,
})

vim.api.nvim_create_autocmd({ "RecordingEnter", "RecordingLeave" }, {
    group = vim.api.nvim_create_augroup("UserMacroStatusline", { clear = true }),
    -- RecordingLeave fires before reg_recording() is cleared.
    callback = function()
        vim.schedule(function()
            vim.cmd("redrawstatus")
        end)
    end,
    desc = "Refresh the mode section when macro recording starts or stops",
})

map("n", "<leader>e", function()
    MiniFiles.open()
end, { desc = "Explore files" })
