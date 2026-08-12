local M = {}

---@return boolean
function M.available()
  return true
end

--- `vim.ui.select` 只給得起「一個動作、沒有預覽」，所以差異靠入口命令承擔：
--- `:TemplateCenter find` 選了就插入、`:TemplateCenter open` 選了就開檔。
---@param entries tc.Entry[]
---@param ctx tc.PickerContext
function M.pick(entries, ctx)
  vim.ui.select(entries, {
    prompt = ctx.prompt .. "：",
    kind = "template-center", -- 讓 dressing 之類的實作可以單獨設定樣式
    ---@param entry tc.Entry
    format_item = function(entry)
      local parts = { entry.name }
      if entry.category ~= "" then
        parts[#parts + 1] = ("(%s)"):format(entry.category)
      end
      if entry.desc ~= "" then
        parts[#parts + 1] = "— " .. entry.desc
      end
      -- 預設實作是 vim.fn.inputlist()，含換行會打亂編號。
      return (table.concat(parts, " "):gsub("[\r\n]", " "))
    end,
  }, function(entry)
    if entry then
      ctx.on_select(entry, ctx)
    end
  end)
end

return M
