# Neovim development setup

A Neovim 0.12+ configuration for Python and Verilog/SystemVerilog development. It uses native `vim.pack`, native `vim.lsp`, Mason, Treesitter, Telescope, blink.cmp, and Conform.

## Prerequisites

### Required

Install these with the package manager available on your operating system:

- Neovim 0.12 or newer (`tiny-cmdline.nvim` and native `vim.pack` require it)
- Git for plugin installation and Git integrations
- `tree-sitter` CLI for compiling Treesitter parsers
- A C toolchain for native parser builds: Clang/GCC and `make` on Unix-like systems, or MSVC Build Tools on Windows
- `rg` (ripgrep) for Telescope live grep
- `lazygit` for the in-editor Git interface
- `curl` or `wget`, plus `tar`, `gzip`, and `unzip`, for plugin and Mason downloads
- Bash and standard Unix utilities for `install.sh`, or PowerShell for `install.ps1` on Windows

### Recommended and optional

- `fd` for faster Telescope file discovery
- `fzf` for command-line fuzzy finding; Telescope works without it in the current configuration
- Node.js and npm, only if you choose to install `basedpyright` through Mason
- A Nerd Font for all plugin icons
- tmux for `vim-tmux-navigator` integration

Check the required commands on a Unix-like system with:

```sh
for cmd in nvim git tree-sitter cc make rg lazygit; do
    command -v "$cmd" >/dev/null || echo "Missing: $cmd"
done
```

On Windows PowerShell:

```powershell
"nvim", "git", "tree-sitter", "rg", "lazygit" | ForEach-Object {
    if (-not (Get-Command $_ -ErrorAction SilentlyContinue)) {
        Write-Host "Missing: $_"
    }
}
```

`fd` and `fzf` can be checked the same way if you install the recommended search tools.

## Installation

Clone the repository first:

```sh
git clone https://github.com/linrswa/nvim-config.git
cd nvim-config
```

### Linux and other Unix-like systems

Linux follows the XDG Base Directory convention. `install.sh` installs to `${XDG_CONFIG_HOME:-$HOME/.config}/nvim`:

```sh
./install.sh
```

To use a non-default config home:

```sh
XDG_CONFIG_HOME=/custom/config/path ./install.sh
```

### Windows

Native Windows Neovim uses `%LOCALAPPDATA%\nvim`, not `XDG_CONFIG_HOME`. Run the PowerShell installer:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The resulting runtime configuration contains only:

```text
nvim/
├── init.lua
├── lua/
└── nvim-pack-lock.json
```

Both installers deliberately exclude `examples/`, `README.md`, installer scripts, `.git/`, and other repository-only files. If an existing configuration is present, it is moved to a timestamped backup before installation. On Unix-like systems, running `install.sh` from a repository already symlinked as `~/.config/nvim` replaces that symlink with a standalone configuration directory.

After installation, start Neovim:

```sh
nvim
```

Native `vim.pack` installs the plugins and updates `nvim-pack-lock.json`. Mason installs `ruff` and `verible` asynchronously; leave Neovim open until installation finishes, then restart it.

`basedpyright` is configured but intentionally excluded from Mason's automatic installation list because Mason installs it through npm. Install it explicitly only after approving that dependency:

```vim
:MasonInstall basedpyright
```

## Included plugins

### Language support and formatting

- `nvim-lspconfig` with native `vim.lsp`
- `mason.nvim` and `mason-lspconfig.nvim`
- `nvim-treesitter` with Python and SystemVerilog parsers
- `blink.cmp` and `blink.lib`
- `conform.nvim`
- `workspace-diagnostics.nvim`
- `tiny-code-action.nvim`

### Navigation and editing

- `telescope.nvim` and `plenary.nvim`
- `harpoon`
- `mini.nvim`: icons, files, statusline, ai, surround, and jump
- `nvim-hlslens`
- `tabout.nvim`
- `TreeSJ`
- `vim-tmux-navigator`

### Interface and Git

- `kanagawa.nvim`
- `tiny-cmdline.nvim`, integrated with blink.cmp
- `gitsigns.nvim`
- `zdiff.nvim`
- `lazygit.nvim`

## Keymaps

The leader key is `<Space>`.

### General

- `<leader>w`: Write the current buffer
- `<leader>q`: Quit the current window
- `<leader>e`: Browse files with mini.files
- `<leader>f`: Format with Ruff or Verible
- `f`, `F`, `t`, `T`, `;`: Enhanced character jumps with mini.jump
- Insert-mode `<Tab>` / `<S-Tab>`: Completion, snippet navigation, then Tabout

### Search and Telescope

- `n`, `N`, `*`, `#`, `g*`, `g#`: Search with hlslens result indicators
- `<leader>l`: Clear search highlights
- `<leader>ff`: Find files
- `<leader>fb`: Find buffers
- `<leader>fc`: Search inside the current buffer
- `<leader>fd`: Show workspace diagnostics
- `<leader>fg`: Live grep; requires `rg`
- `<leader>fh`: Search help tags
- `<leader>fk`: Search keymaps

### LSP and diagnostics

- `gd`: Go to definition
- `gr`: Find references
- `K`: Show hover documentation
- `<leader>rn`: Rename symbol
- `<leader>ca`: Open tiny-code-action in Telescope
- `[d`, `]d`: Previous or next diagnostic
- `<leader>d`: Show diagnostic details

Workspace diagnostics are populated automatically when an LSP client attaches. `<leader>fd` displays the collected diagnostics through Telescope.

### Harpoon

- `<leader>a`: Add the current file
- `<leader>h`: Open the Harpoon menu
- `<leader>1`–`<leader>4`: Jump to Harpoon entries 1–4
- `<C-S-P>`, `<C-S-N>`: Previous or next Harpoon entry

### TreeSJ

- `<leader>m`: Toggle split/join for the syntax node under the cursor
- `<leader>j`: Join the syntax node
- `<leader>s`: Split the syntax node

### Git and diff

- `<leader>gg`: Open LazyGit at the current file's Git project
- `[c`, `]c`: Previous or next Git hunk
- `<leader>gs`, `<leader>gr`: Stage or reset the current hunk
- Visual `<leader>gs`, `<leader>gr`: Stage or reset the selected hunk
- `<leader>gS`, `<leader>gR`: Stage or reset the current buffer
- `<leader>gp`: Preview the current hunk
- `<leader>gb`: Show full blame for the current line
- `<leader>gd`: Diff against the Git index
- `<leader>gD`: Diff against the previous commit
- `ih` in operator-pending or Visual mode: Select a Git hunk
- `<leader>zd`: Open Zdiff for uncommitted changes
- `<leader>zD`: Open Zdiff against `main`

## Language notes

- Python uses Ruff for LSP features and formatting.
- `basedpyright` provides Python type checking when installed separately.
- Verilog and SystemVerilog use Verible for LSP features and formatting.
- Both HDL filetypes use the Treesitter SystemVerilog parser.

Use `:Mason` to inspect external tool installation and `:checkhealth` to diagnose the environment.
