local blink = require("blink.cmp")

local function tabout(direction)
    require("tabout")[direction]()
    return true
end

vim.lsp.config("*", {
    capabilities = blink.get_lsp_capabilities(),
})

blink.setup({
    keymap = {
        preset = "default",
        ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
        ["<CR>"] = { "accept", "fallback" },
        ["<Tab>"] = { "select_next", "snippet_forward", function()
            return tabout("tabout")
        end },
        ["<S-Tab>"] = { "select_prev", "snippet_backward", function()
            return tabout("taboutBack")
        end },
    },
    completion = {
        documentation = {
            auto_show = true,
            auto_show_delay_ms = 200,
        },
    },
    sources = {
        default = { "lsp", "path", "buffer", "snippets" },
    },
    -- Keep first launch independent of Cargo and prebuilt fuzzy binaries.
    fuzzy = {
        implementation = "lua",
    },
})
