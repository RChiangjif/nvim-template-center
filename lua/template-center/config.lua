local M = {}

---@class tc.CaptureConfig
---@field dedent boolean 去掉選取範圍的共同前導空白
---@field ask_category boolean 存檔時詢問分類（目錄）
---@field ask_description boolean 存檔時詢問說明

---@class tc.InsertConfig
---@field position "below"|"above"|"top" 預設插入位置
---@field reindent boolean 依游標所在行的縮排對齊模板
---@field snippet "auto"|boolean 是否用 vim.snippet 展開 placeholder
---@field top_after string[] position="top" 時，插在最後一行符合這些 pattern 之後

---@class tc.ExplorerConfig
---@field side "left"|"right"
---@field width integer
---@field indent integer 每一層縮排的空白數
---@field confirm boolean 套用檔案變更前先確認
---@field trash boolean 刪除時搬到 .trash/ 而非真的刪掉
---@field keymaps table<string, string|false>

---@class tc.Config
---@field dir string 模板庫根目錄
---@field picker "auto"|"telescope"|"select"
---@field extensions table<string, string> filetype → 副檔名
---@field capture tc.CaptureConfig
---@field insert tc.InsertConfig
---@field explorer tc.ExplorerConfig

---@type tc.Config
local defaults = {
  dir = vim.fs.joinpath(vim.fn.stdpath("data"), "template-center"),

  picker = "auto",

  -- 只在來源 buffer 沒有副檔名可抄時才會用到。
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
    -- 設成 false 可停用單一按鍵。這個 buffer 是可以編輯的，所以刻意不佔用
    -- o / O / dd / cc / p / x / u —— 新增檔案就是 o 打一行，刪除就是 dd。
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

  -- keymaps 是「使用者說了算」的表：deep_extend 會保留預設鍵，所以整表覆寫時
  -- 想拿掉某個鍵要設成 false（而不是省略），這裡把 false 清乾淨。
  for lhs, action in pairs(M.options.explorer.keymaps) do
    if action == false then
      M.options.explorer.keymaps[lhs] = nil
    end
  end

  M.options.dir = vim.fs.normalize(M.options.dir)
  return M.options
end

return M
