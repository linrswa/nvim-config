# Neovim development setup

A Neovim 0.12+ configuration for Python and Verilog/SystemVerilog development. It uses native `vim.pack`, native `vim.lsp`, Mason, Treesitter, Telescope, blink.cmp, and Conform.

## Requirements

- Neovim 0.12 or newer
- Git
- `tree-sitter` CLI for compiling parsers
- `rg` (ripgrep) for Telescope live grep
- `lazygit` for the in-editor Git interface
- A C compiler and `make` for native parser builds
- npm only if you choose to install `basedpyright` through Mason

On macOS, the external command-line dependencies can be installed with Homebrew:

```sh
brew install tree-sitter-cli ripgrep lazygit
```

## Installation

Clone, copy, or symlink this directory to Neovim's configuration location:

- macOS/Linux: `~/.config/nvim`
- Windows: `%LOCALAPPDATA%\nvim`

Example using a symlink:

```sh
mkdir -p ~/.config
ln -s /path/to/this/repository ~/.config/nvim
```

Start Neovim after installation:

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
