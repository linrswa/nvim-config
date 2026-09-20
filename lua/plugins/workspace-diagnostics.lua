local workspace_diagnostics = require("workspace-diagnostics")

workspace_diagnostics.setup()

vim.lsp.config("*", {
    on_attach = function(client, bufnr)
        if client:supports_method("workspace/diagnostic", bufnr) then
            vim.lsp.buf.workspace_diagnostics({ client_id = client.id })
        else
            workspace_diagnostics.populate_workspace_diagnostics(client, bufnr)
        end
    end,
})
