--- nvim-template-center：競賽程式模板庫。
---
---   * visual mode 框選 → 命名 → 存進模板庫
---   * 搜尋視窗（telescope，沒裝就退回 vim.ui.select）依名稱找模板並插入
---   * 可展開收合、而且可以直接編輯的模板庫側邊欄
local M = {}

---@param opts tc.Config?
function M.setup(opts)
  require("template-center.config").setup(opts)
  require("template-center.commands").setup()
end

--- 把選取範圍（沒有 range 就是整個 buffer）存成模板。
---@param opts { line1: integer?, line2: integer?, bufnr: integer?, name: string? }?
function M.save(opts)
  require("template-center.capture").save(opts)
end

--- 從 visual mode 呼叫：先離開 visual mode 讓 '< '> 落定，再讀取範圍。
function M.save_selection()
  vim.cmd('execute "normal! \\<Esc>"')
  local line1 = vim.fn.line("'<")
  local line2 = vim.fn.line("'>")
  require("template-center.capture").save({ line1 = line1, line2 = line2 })
end

--- 開搜尋視窗，選了就插入目前的 buffer。
---@param opts table?
function M.find(opts)
  require("template-center.picker").find(opts)
end

--- 開搜尋視窗，選了就開啟模板檔本身來編輯。
---@param opts table?
function M.edit(opts)
  require("template-center.picker").open(opts)
end

--- 直接依名稱插入。
---@param name string
---@param opts table?
function M.insert(name, opts)
  require("template-center.insert").insert(name, opts)
end

---@param opts { focus: boolean?, reveal: string? }?
function M.toggle_tree(opts)
  require("template-center.explorer").toggle(opts)
end

---@param opts { focus: boolean?, reveal: string? }?
function M.open_tree(opts)
  require("template-center.explorer").open(opts)
end

--- 模板庫根目錄。
---@return string
function M.root()
  return require("template-center.store").root()
end

return M
