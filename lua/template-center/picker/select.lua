local M = {}

---@return boolean
function M.available()
  return true
end

--- `vim.ui.select` can only offer one action and no preview, so the difference
--- is carried by the entry points instead: `:TemplateCenter find` inserts what
--- you pick, `:TemplateCenter edit` opens it.
---@param entries tc.Entry[]
---@param ctx tc.PickerContext
function M.pick(entries, ctx)
  vim.ui.select(entries, {
    prompt = ctx.prompt .. ":",
    kind = "template-center", -- lets implementations like dressing style this one specifically
    ---@param entry tc.Entry
    format_item = function(entry)
      local parts = { entry.name }
      if entry.category ~= "" then
        parts[#parts + 1] = ("(%s)"):format(entry.category)
      end
      if entry.desc ~= "" then
        parts[#parts + 1] = "— " .. entry.desc
      end
      -- The default implementation is vim.fn.inputlist(); a newline in here
      -- would break its numbering.
      return (table.concat(parts, " "):gsub("[\r\n]", " "))
    end,
  }, function(entry)
    if entry then
      ctx.on_select(entry, ctx)
    end
  end)
end

return M
