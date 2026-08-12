local M = {}

---@class tc.CaptureConfig
---@field dedent boolean strip the selection's common leading whitespace
---@field ask_category boolean ask for a category (directory) when saving
---@field ask_description boolean ask for a description when saving

---@class tc.InsertConfig
---@field position "below"|"above"|"top" where to put the template by default
---@field reindent boolean match the indentation of the line the cursor is on
---@field snippet "auto"|boolean expand placeholders through vim.snippet
---@field top_after string[] with position="top", insert after the last line matching these

---@class tc.ExplorerConfig
---@field side "left"|"right"
---@field width integer
---@field indent integer spaces per tree level
---@field confirm boolean confirm before applying file changes
---@field trash boolean delete into .trash/ instead of unlinking
---@field keymaps table<string, string|false>

---@class tc.Config
---@field dir string root of the template library
---@field picker "auto"|"telescope"|"select"
---@field extensions table<string, string> filetype → extension
---@field capture tc.CaptureConfig
---@field insert tc.InsertConfig
---@field explorer tc.ExplorerConfig

---@type tc.Config
local defaults = {
  dir = vim.fs.joinpath(vim.fn.stdpath("data"), "template-center"),

  picker = "auto",

  -- Only consulted when the source buffer has no extension to copy.
  extensions = {
    c = "c",
    cpp = "cpp",
    csharp = "cs",
    go = "go",
    haskell = "hs",
    java = "java",
    javascript = "js",
    kotlin = "kt",
    lua = "lua",
    ocaml = "ml",
    pascal = "pas",
    python = "py",
    ruby = "rb",
    rust = "rs",
    sh = "sh",
    typescript = "ts",
  },

  capture = {
    dedent = true,
    ask_category = true,
    ask_description = true,
  },

  insert = {
    position = "below",
    reindent = true,
    snippet = "auto",
    top_after = { "^#include", "^#pragma", "^using%s+namespace", "^import%s", "^from%s+%S+%s+import" },
  },

  explorer = {
    side = "left",
    width = 34,
    indent = 2,
    confirm = true,
    trash = true,
    -- Set any entry to false to drop that mapping. This buffer is editable, so
    -- o / O / dd / cc / p / x / u are deliberately left alone: you add a file by
    -- typing a line with `o` and delete one with `dd`.
    keymaps = {
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
}

---@type tc.Config
M.options = vim.deepcopy(defaults)

M.defaults = defaults

---@param opts tc.Config?
---@return tc.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  -- keymaps is a table the user owns: deep_extend keeps the defaults around, so
  -- dropping one means setting it to false rather than omitting it. Clear those
  -- out here.
  for lhs, action in pairs(M.options.explorer.keymaps) do
    if action == false then
      M.options.explorer.keymaps[lhs] = nil
    end
  end

  M.options.dir = vim.fs.normalize(M.options.dir)
  return M.options
end

return M
