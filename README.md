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
├── after/
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
- `zdiff.nvim`
- `lazygit.nvim`

## Keymaps

The leader key is `<Space>`.

### General

- `<leader>w`: Write the current buffer
- `<leader>q`: Quit the current window
- `<leader>e`: Browse files with mini.files
- `<leader>f`: Format the buffer with Ruff or Verible; in visual `v`/`V` mode, format the selection
- `f`, `F`, `t`, `T`, `;`: Enhanced character jumps with mini.jump
- Insert-mode `<Tab>` / `<S-Tab>`: Completion, snippet navigation, then Tabout

Visual formatting uses Ruff's native range formatting for Python and Verible's native `--lines` for Verilog/SystemVerilog. Python selections skip import organization; normal-mode formatting still organizes imports and formats the whole buffer. Selection formatting can expand to complete lines/statements as required by the formatter, rather than editing an arbitrary substring. `Ctrl-v` blockwise selections are rejected with a warning. Other filetypes retain Conform's LSP fallback (range formatting requires server support). No automatic save is performed.

Formatting regression test (requires installed Conform, Ruff, and Verible; Mason binaries are supported):

```sh
nvim --headless -u NONE -i NONE -l tests/formatting.lua
```

### Search and Telescope

- `n`, `N`, `*`, `#`, `g*`, `g#`: Search with hlslens result indicators
- `<leader>l`: Clear search highlights
- `<leader>ff`: Find files
- `<leader>fp`: Find and paste a file/folder path into the current buffer
- `<leader>fb`: Find buffers
- `<leader>fc`: Search inside the current buffer
- `<leader>fd`: Show workspace diagnostics
- `<leader>fg`: Live grep; requires `rg`
- `<leader>fh`: Search help tags
- `<leader>fk`: Search keymaps

#### Find and paste paths

`<leader>fp` works in any modifiable buffer, including `.hdl-sources`, code, and Markdown. Telescope lists files and folders (folders end in `/`); Enter inserts the selected path **before the character under the original cursor**, or into an empty line. Esc cancels. It does not touch registers/the clipboard, save the buffer, or open the selected file. Undo with `u`. Split/tab selection keys also paste rather than opening a file. This one-shot picker is not cached for `:Telescope resume`; use `<leader>fp` again to choose a new insertion target.

Search and inserted paths share the same root, shown in the picker title: the nearest ancestor containing `.git`, `.hg`, `.hdl-sources`, `CMakeLists.txt`, `pyproject.toml`, `package.json`, or `Cargo.toml`; otherwise the current working directory. Paths are plain project-relative text, without quoting/escaping (not automatically relative to a Markdown document). For `.hdl-sources`, use an empty line, then save with `:w` to run its existing scan.

Discovery is chunked and needs no extra executable. It includes dotfiles and does **not** apply `.gitignore`; it skips symlinks, names containing newlines, and directories named `.git`, `.hg`, `.svn`, `node_modules`, `.venv`, `venv`, `__pycache__`, `.cache`, `build`, `dist`, `target`, or `obj_dir`. Unreadable directories are skipped with a warning. Large trees may take time to populate; Esc cancels the scan.

Regression test (requires the installed Telescope/Plenary packages):

```sh
nvim --headless -u NONE -l tests/path_picker.lua
```

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
- `<leader>zd`: Open Zdiff for uncommitted changes
- `<leader>zD`: Open Zdiff against `main`

## Language notes

- Python uses Ruff for LSP features and formatting.
- `basedpyright` provides Python type checking when installed separately.
- Verilog and SystemVerilog use Verible for LSP features and formatting. Conform uses the `verible` formatter with `--port_declarations_alignment=align`.
- Both HDL filetypes use the Treesitter SystemVerilog parser.
- `after/indent/systemverilog.lua` supplements the built-in SystemVerilog indentation: leading `)` aligns with the matching opening parenthesis's line, and `endmodule` aligns with its matching `module`. Matching ignores comments, strings, and escaped identifiers; other lines retain the built-in rules. This affects typing and `=` indentation, not `<leader>f` formatting.

Use `:Mason` to inspect external tool installation and `:checkhealth` to diagnose the environment.

## HDL source scope and templates

Commands use the nearest `.hdl-sources`, `.git`, or `CMakeLists.txt` project root.

- `:HdlSources` opens the project's **real, editable `.hdl-sources` buffer** in a float. Use `:w` to save and scan; `:q` to close. Opening it does not write a spec or scan the project.
- `:VeribleScan` scans the saved spec and generates `verible.filelist`; `:VeribleScan!` suppresses success notifications (not errors).
- `:HdlInstance` (existing HDL `<leader>fi`) and `:HdlTestbench` immediately open a **file-first** Telescope picker from the existing filelist. No new keymaps are added.
- `:VerilatorLint` lints using the existing filelist and unsaved buffer overlays. Opening an existing normal HDL file (`BufReadPost`), editing, and saving trigger debounced lint, but **never rescan**. Scratch/preview buffers are skipped on open; simply switching buffers does not trigger another run. Automatic lint requires an existing `verible.filelist`. Saving `.hdl-sources` triggers a scan instead.

Example `.hdl-sources` for a project with `src/` RTL and separate `tb/` benches:

```text
# One relative file or directory per line
src/
# Exclusions apply to all includes, regardless of order
!src/experimental/
```

Blank lines and whole-line `#` / `//` comments are ignored. `!path` excludes that file or directory subtree. Paths are relative to the spec directory; absolute paths, parent traversal, globs, quoting and variable/home expansion are not supported. There are no inline comments. Only `.v` and `.sv` files enter the list; directory symlinks are never followed (currently all symlink entries are skipped). There are no implicit directory exclusions: name exclusions explicitly if needed. `.` explicitly opts into the whole project, but a missing/empty spec **never implicitly falls back to a root scan**. Empty scope writes an empty filelist.

Scanning yields between chunks, sorts/deduplicates plain relative paths, preserves the old list on any error, and atomically renames a same-directory temporary file on success. Identical lists are not rewritten. Superseded local scans cannot publish; the saved spec is also checked again before publication to catch changes made by another editor. This is not a filesystem transaction: concurrent changes to the source tree or a spec write at the exact check/rename boundary require another scan. Unsupported/ambiguous filelist path spellings are rejected rather than escaped.

### Lazy parsing and insertion

File selection shows `Loading…`, debounces about 120 ms, then asynchronously runs `verible-verilog-syntax` on the **saved source**, not an unsaved source buffer. Only the focused file is parsed, with at most one worker; focus changes and closing cancel obsolete work. Stale results cannot replace a newer preview. A memory-only cache uses file size, mtime/ctime (including nanoseconds), and HDL-save invalidation. Verible is found on PATH or in the existing Mason bin directory.

Enter while loading only notifies. A file with one supported module inserts below the original anchored cursor line; several modules open a second module picker. Escape/cancel inserts nothing. Parse/render failures insert nothing. Unsupported sibling modules are reported as warnings without hiding supported modules; a module whose testbench cannot be safely rendered remains visibly unavailable without blocking its valid siblings. Existing instance and testbench layouts are retained.

This is a conservative ANSI-module workflow, **not a general SystemVerilog elaborator**. Non-ANSI/complex ports, required/type parameters, conditional preprocessing/includes and other unsupported interfaces are rejected. Instance parameter defaults that depend on module scope remain empty named overrides. Testbench generation must copy types/constants into a new scope, so it is stricter: only untyped/`int` nonnegative decimal parameter defaults fitting signed 32-bit are supported; scoped defaults, header localparams, unknown dimension identifiers, inout driving and unsupported type/expression cases report an error instead of silently coercing to `int` or generating broken references. Manually complete the generated check task and test cases; the skeleton is not a functional verification suite.

### Lint behavior and remaining performance limits

Live lint includes the current `.v`/`.sv` buffer alongside the RTL filelist even when the current testbench is excluded from that list (including a current source under `build/` or `obj_dir/`). It does not add the bench to `verible.filelist` or save the buffer. Snapshot overlays skip unnamed buffers and directory buffers (including symlinks to directories), while retaining named, not-yet-saved files. Set `b:verilator_top_module` / `g:verilator_top_module` when needed; existing `verilator_lint_args` settings still apply.

The inherited lint snapshot **still synchronously mirrors the project tree** on each debounced lint run. Large repositories can therefore still stall during live lint; this change removes save-time source rescans and eager picker parsing, not all possible editor latency. Snapshot directory symlinks, external source paths/includes and excluded-directory dependencies are not general unsaved overlays. Scans use chunked synchronous filesystem calls (a single directory read can still be slow), and reading the focused saved source/decoding its CST remains on Neovim's main thread. There is no persistent index, background watcher or automatic scan on every HDL save.

### HDL regression checks

From this repository (no install/sync required):

```sh
nvim --headless -u NONE -l tests/hdl.lua
nvim --headless -u NONE -l tests/hdl_open.lua
nvim --headless -u NONE -i NONE -l tests/hdl_snapshot.lua
```

Requires real Verible (`~/.local/share/nvim/mason/bin/verible-verilog-syntax` for the direct renderer fixtures), Verilator on PATH, and the installed Telescope/Plenary packages under Neovim's standard data `site/pack/core/opt/` directory. Tests use disposable project directories, isolated runtime configuration and real parser/linter processes. Coverage includes scoped sorted/deduplicated discovery, symlink cycles, missing/invalid specs, unchanged writes, stale/cross-editor scans, parser worker cancellation/cache invalidation, mixed supported/unsupported modules, real Telescope loading/insertion/multiple-module/cancel and delayed-preview races, conservative TB rejection, and excluded unsaved TB diagnostics followed by a completed repaired lint run. The snapshot regression separately covers unnamed/directory buffers, named unsaved overlays, preservation of source files on disk, and temporary snapshot cleanup using real Verilator. No user RTL, live configuration, or project filelist is modified by these tests.

`examples/test.py` is an intentionally ill-typed example, not a Python test suite.
