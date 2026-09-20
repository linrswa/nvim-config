require("vim._core.ui2").enable({})

local tiny_cmdline = require("tiny-cmdline")

tiny_cmdline.setup({
    on_reposition = tiny_cmdline.adapters.blink,
})
