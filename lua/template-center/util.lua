local M = {}

local TITLE = "template-center"

---@param msg string
---@param level integer? vim.log.levels，預設 INFO
function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = TITLE })
end

---@param msg string
function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

---@param msg string
function M.error(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

--- 去掉所有非空行的共同前導空白。
---@param lines string[]
---@return string[]
function M.dedent(lines)
  local prefix ---@type string?
  for _, line in ipairs(lines) do
    if line:match("%S") then
      local indent = line:match("^[ \t]*")
      if prefix == nil then
        prefix = indent
      else
        -- 取兩者的共同前綴，tab 與空白混用時也不會切錯位置。
        local i = 0
        while i < #prefix and i < #indent and prefix:sub(i + 1, i + 1) == indent:sub(i + 1, i + 1) do
          i = i + 1
        end
        prefix = prefix:sub(1, i)
      end
      if prefix == "" then
        return lines
      end
    end
  end

  if not prefix or prefix == "" then
    return lines
  end

  local out = {}
  for i, line in ipairs(lines) do
    out[i] = line:sub(#prefix + 1)
  end
  return out
end

--- 去掉頭尾的空行（存模板時 visual 選取常常多帶一行）。
---@param lines string[]
---@return string[]
function M.trim_blank_lines(lines)
  local first, last = 1, #lines
  while first <= last and not lines[first]:match("%S") do
    first = first + 1
  end
  while last >= first and not lines[last]:match("%S") do
    last = last - 1
  end
  return vim.list_slice(lines, first, last)
end

--- 檔名（不是路徑）合法性檢查。
---@param name string
---@return boolean ok
---@return string? err
function M.validate_name(name)
  if name == "" then
    return false, "名稱不可為空"
  end
  if name == "." or name == ".." then
    return false, ("名稱不可為 %q"):format(name)
  end
  if name:find("/") or name:find("\\") then
    return false, ("名稱不可含路徑分隔符號：%q"):format(name)
  end
  if name:find("^%.") then
    return false, ("名稱不可以 . 開頭：%q"):format(name)
  end
  return true
end

--- 相對路徑合法性檢查（允許 `/` 當分類分隔）。
---@param relpath string
---@return boolean ok
---@return string? err
function M.validate_relpath(relpath)
  if relpath == "" then
    return false, "路徑不可為空"
  end
  if relpath:find("^/") or relpath:match("^%a:") then
    return false, "不接受絕對路徑"
  end
  for part in vim.gsplit(relpath, "/", { plain = true }) do
    local ok, err = M.validate_name(part)
    if not ok then
      return false, err
    end
  end
  return true
end

--- 把使用者輸入的名稱整理成可用的檔名：空白轉底線、砍掉危險字元。
---@param name string
---@return string
function M.sanitize(name)
  name = vim.trim(name)
  name = name:gsub("%s+", "_")
  name = name:gsub("[<>:\"|?*%z]", "")
  name = name:gsub("/+", "/")
  name = name:gsub("^/+", ""):gsub("/+$", "")
  return name
end

--- 決定模板檔要用哪個副檔名：優先抄來源 buffer 的，否則查設定表。
---@param bufnr integer
---@return string ext 不含點；抓不到時回傳 "txt"
function M.extension_for(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local ext = name ~= "" and name:match("%.([%w_]+)$") or nil
  if ext then
    return ext
  end

  local ft = vim.bo[bufnr].filetype
  local mapped = require("template-center.config").options.extensions[ft]
  return mapped or (ft ~= "" and ft) or "txt"
end

--- 判斷一個視窗是否適合當「插入目標 / 開檔目標」。
---@param win integer?
---@return boolean
function M.is_usable_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false -- 浮動視窗
  end
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" or vim.bo[buf].buftype == "acwrite"
end

--- 找一個可以拿來開檔的一般視窗，找不到就開一個。
---@param prefer integer? 優先使用的視窗
---@return integer win
function M.pick_target_win(prefer)
  if M.is_usable_win(prefer) then
    return prefer --[[@as integer]]
  end
  local cur = vim.api.nvim_get_current_win()
  if M.is_usable_win(cur) and vim.bo[vim.api.nvim_win_get_buf(cur)].filetype ~= "templatecenter" then
    return cur
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if M.is_usable_win(win) and vim.bo[buf].filetype ~= "templatecenter" then
      return win
    end
  end
  vim.cmd("vsplit")
  return vim.api.nvim_get_current_win()
end

return M
