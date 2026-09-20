require("gitsigns").setup({
    on_attach = function(bufnr)
        local gitsigns = require("gitsigns")

        local function map(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
        end

        map("n", "]c", function()
            if vim.wo.diff then
                vim.cmd.normal({ "]c", bang = true })
            else
                gitsigns.nav_hunk("next")
            end
        end, "Next git hunk")

        map("n", "[c", function()
            if vim.wo.diff then
                vim.cmd.normal({ "[c", bang = true })
            else
                gitsigns.nav_hunk("prev")
            end
        end, "Previous git hunk")

        map("n", "<leader>gs", gitsigns.stage_hunk, "Stage git hunk")
        map("n", "<leader>gr", gitsigns.reset_hunk, "Reset git hunk")
        map("x", "<leader>gs", function()
            gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
        end, "Stage selected git hunk")
        map("x", "<leader>gr", function()
            gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
        end, "Reset selected git hunk")

        map("n", "<leader>gS", gitsigns.stage_buffer, "Stage git buffer")
        map("n", "<leader>gR", gitsigns.reset_buffer, "Reset git buffer")
        map("n", "<leader>gp", gitsigns.preview_hunk, "Preview git hunk")
        map("n", "<leader>gb", function()
            gitsigns.blame_line({ full = true })
        end, "Blame git line")
        map("n", "<leader>gd", gitsigns.diffthis, "Diff against git index")
        map("n", "<leader>gD", function()
            gitsigns.diffthis("~")
        end, "Diff against previous commit")

        map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "Select git hunk")
    end,
})
