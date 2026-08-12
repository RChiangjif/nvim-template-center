# nvim-template-center

A template library for competitive programming, kept inside Neovim.

- **Select and save** — grab a snippet in visual mode, name it, and it's in the library
- **Type a name to get it back** — telescope picker (falls back to `vim.ui.select` when telescope
  isn't installed), pick one and it lands at your cursor
- **Edit the library directly** — a nerdtree-style collapsible tree that is also a fully editable
  buffer, oil-style: edit a line to rename, `dd` to delete, indent a line to move it into that
  directory. Nothing touches disk until you `:w`.

Requires Neovim 0.10+ (uses `vim.uv`, `vim.fs`, `vim.snippet`). telescope is optional.

## Installation

With lazy.nvim:

```lua
{
  "RChiangjif/nvim-template-center",
  dependencies = { "nvim-telescope/telescope.nvim" }, -- optional
  cmd = "TemplateCenter",
  keys = {
    { "<leader>ts", ":TemplateCenter save<CR>", mode = "v", desc = "Save as template" },
    { "<leader>tf", "<cmd>TemplateCenter find<CR>", desc = "Find and insert template" },
    { "<leader>tt", "<cmd>TemplateCenter tree<CR>", desc = "Template library sidebar" },
  },
  opts = {},
}
```

`opts = {}` gives you the defaults. Calling `setup()` is optional — the commands register either way.

## Usage

### Saving a template

Select in visual mode, then `<leader>ts` (or `:'<,'>TemplateCenter save [name]`). You'll be asked for:

1. **Name** — `dinic` works; so does `cpp/graph/dinic`, where slashes are the category path
2. **Category** — defaults to the current buffer's filetype (`cpp` in a `.cpp` file); leave empty
   for the top level
3. **Description** — optional, shown in the picker and searchable

Templates are stored as **real files**. The extension is taken from the source file (falling back to
the `extensions` table). The selection's common indentation is stripped; relative indentation inside
it is preserved.

Without a range (`:TemplateCenter save`), the whole buffer is saved.

### Finding and inserting

`:TemplateCenter find`, or `:Telescope template_center`. Name, category and description are all
fuzzy-searchable.

| Key | Action |
| --- | --- |
| `<CR>` | Insert into the buffer you came from |
| `<C-e>` | Open the template file itself for editing |
| `<C-y>` | Copy to a register, paste it yourself with `p` |
| `<C-o>` | Open the sidebar with this template revealed |

The template is re-indented to match the line your cursor is on. If the cursor sits on a blank line,
the template replaces it instead of pushing it down.

Without telescope, the picker falls back to `vim.ui.select`. That hook only offers "pick one item",
so "pick one and open it for editing" lives in a separate command, `:TemplateCenter edit`.
dressing.nvim, snacks.nvim and fzf-lua all take over `vim.ui.select` themselves — whichever one you
have installed is what the fallback will look like, with no extra configuration.

### The sidebar

`:TemplateCenter tree`.

```
cpp/
  graph/
    dinic.cpp
    scc.cpp
  math/
    modint.cpp
py/
  io.py
```

**This buffer is editable**, so `o`, `dd`, `cc`, `p` and `u` all keep their usual meaning:

| What you do | What happens on write |
| --- | --- |
| Edit the text on a line | Rename (extension included) |
| `dd` | Delete — moved to `.trash/` by default, not actually removed |
| `o` and type a line | New empty template; end it with `/` to create a directory |
| Indent a line one level | Move it into the directory above |
| Outdent a line | Move it out |
| `yyp` then rename | Make a copy |

**Structure is expressed through indentation**, so don't put slashes in names — indent instead. On
`:w` you get a list of every operation to confirm, and they are applied together. If any line is
invalid (indentation jump, duplicate name in the same level, target already exists, …) the whole
write is rejected with the offending line number. It never applies half of your edit.

| Key | Action |
| --- | --- |
| `<CR>` | Directory: expand/collapse. File: open it |
| `<Tab>` | Expand/collapse without opening |
| `<C-s>` / `<C-t>` | Open in a split / new tab |
| `<C-p>` | Preview in a floating window |
| `gi` | Insert this template into the buffer you came from |
| `gr` | Reload, discarding unsaved edits |
| `g?` | Help |
| `q` | Close the sidebar (this shadows macro recording; set it to `false` if you mind) |

Children of a collapsed directory are never rendered, so they never enter the diff — saving with
directories collapsed can't make files you couldn't see disappear.

### Snippet placeholders

Templates may contain `${1:n}` and `$0`:

```cpp
struct SegTree {
    int n = ${1:MAXN};
    $0
};
```

When a template contains `$<digit>`, it is inserted through `vim.snippet.expand` so you can `<Tab>`
between placeholders (`vim.snippet.jump`, bound by default in Neovim 0.11). Detection is limited to
the `$1` / `${1:...}` shape, so a lone `$` in a shell or LaTeX template won't trigger it. Set
`insert.snippet = false` if it ever gets in the way.

## Configuration

```lua
require("template-center").setup({
  dir = vim.fs.joinpath(vim.fn.stdpath("data"), "template-center"),
  picker = "auto",              -- "auto" | "telescope" | "select"

  -- Used when the source buffer has no extension to copy
  extensions = { cpp = "cpp", python = "py", rust = "rs", --[[ … ]] },

  capture = {
    dedent = true,              -- strip the selection's common indentation
    ask_category = true,
    ask_description = true,
  },

  insert = {
    position = "below",         -- "below" | "above" | "top"
    reindent = true,            -- match the indentation of the cursor line
    snippet = "auto",           -- "auto" | true | false
    -- With position = "top", insert after the last line matching these
    top_after = { "^#include", "^#pragma", "^using%s+namespace", "^import%s" },
  },

  explorer = {
    side = "left",              -- "left" | "right"
    width = 34,
    indent = 2,                 -- spaces per tree level
    confirm = true,             -- confirm before applying changes
    trash = true,               -- delete into .trash/ instead of unlinking
    keymaps = {                 -- set any of these to false to disable
      ["<CR>"] = "open_or_toggle",
      ["<Tab>"] = "toggle",
      ["<C-s>"] = "open_split",
      ["<C-t>"] = "open_tab",
      ["<C-p>"] = "preview",
      ["gi"] = "insert",
      ["gr"] = "refresh",
      ["g?"] = "help",
      ["q"] = "close",
    },
  },
})
```

## What the library looks like on disk

By default, `~/.local/share/nvim/template-center/`:

```
template-center/
├── cpp/graph/dinic.cpp        ← templates are ordinary files
├── py/io.py
├── .template-center.json      ← descriptions and sidebar expansion state
└── .trash/20260813-013000/…   ← whatever the sidebar deleted
```

Because templates are ordinary files, pointing `dir` at your own git repository gets you version
control and sync across machines, and any other editor can open them. The JSON file is decoration —
lose it and your templates are still there.

## Commands

```
:TemplateCenter find          Search and insert (the default with no subcommand)
:'<,'>TemplateCenter save     Save the selection as a template
:TemplateCenter insert <name> Insert by name, with completion
:TemplateCenter edit          Search and open the template file for editing
:TemplateCenter tree          Toggle the sidebar
:TemplateCenter root          Open the library directory in a normal window
```

Lua API on `require("template-center")`: `.save()`, `.save_selection()`, `.find()`, `.edit()`,
`.insert(name)`, `.toggle_tree()`, `.root()`.

## Development

```sh
make test   # 53 headless assertions, no external dependencies
make dev    # a clean Neovim to play in; library at stdpath('cache')/template-center-dev
```

The suite covers the store's file operations, the sidebar's parse/diff/apply pipeline (renaming a
parent and its child in one write, swapping two names, collapsed directories staying untouched), and
an end-to-end walk through the whole workflow. If telescope happens to be installed on the machine,
that backend gets exercised too.
