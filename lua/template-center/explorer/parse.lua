local util = require("template-center.util")

--- 把使用者編輯過的 buffer 內容讀回成一棵樹。純函式，不碰檔案系統。
---
--- 樹的結構是由**縮排**決定的，不是由 id 決定 —— 所以把一行往右推一層就等於
--- 把它搬進上面那個目錄。任何一項驗證失敗都整批中止（不做半套），並回報行號。
local M = {}

---@class tc.ParsedNode
---@field id integer? 沒有 id 表示是新增的
---@field name string
---@field type "file"|"directory"
---@field depth integer
---@field lnum integer
---@field path string 新座標下的相對路徑

---@class tc.ParseError
---@field lnum integer
---@field msg string

---@param lines string[]
---@param opts { indent: integer }?
---@return tc.ParsedNode[]? nodes
---@return tc.ParseError? err
function M.parse(lines, opts)
  local unit = math.max((opts and opts.indent) or 2, 1)

  local nodes = {} ---@type tc.ParsedNode[]
  local stack = {} ---@type table<integer, tc.ParsedNode> depth → 該層最後看到的節點
  local taken = {} ---@type table<string, integer> "父路徑\0名稱" → 行號
  local prev_depth = -1

  for lnum, line in ipairs(lines) do
    if line:match("%S") then -- 空行忽略
      local id, rest = line:match("^/(%d+)%s(.*)$")
      if not id then
        rest = line
      end

      local ws, body = rest:match("^([ \t]*)(.*)$")

      -- tab 算一整層，避免 expandtab 沒開的人怎麼縮排都對不上。
      local width = 0
      for ch in ws:gmatch(".") do
        width = width + (ch == "\t" and unit or 1)
      end
      local depth = math.floor(width / unit)

      local name = vim.trim(body)
      local is_dir = name:sub(-1) == "/"
      if is_dir then
        name = (name:gsub("/+$", ""))
      end

      local ok, err = util.validate_name(name)
      if not ok then
        return nil, { lnum = lnum, msg = err --[[@as string]] }
      end

      if depth > prev_depth + 1 then
        return nil, { lnum = lnum, msg = "縮排一次跳了超過一層" }
      end

      local parent = depth > 0 and stack[depth - 1] or nil
      if depth > 0 then
        if not parent then
          return nil, { lnum = lnum, msg = "找不到上一層的目錄" }
        end
        if parent.type ~= "directory" then
          return nil, { lnum = lnum, msg = ("上一層 %q 不是目錄，不能放東西進去"):format(parent.name) }
        end
      end

      local parent_path = parent and parent.path or ""
      local key = parent_path .. "\0" .. name
      if taken[key] then
        return nil, { lnum = lnum, msg = ("同一層已經有 %q 了（第 %d 行）"):format(name, taken[key]) }
      end
      taken[key] = lnum

      ---@type tc.ParsedNode
      local node = {
        id = id and tonumber(id) or nil,
        name = name,
        type = is_dir and "directory" or "file",
        depth = depth,
        lnum = lnum,
        path = parent_path ~= "" and (parent_path .. "/" .. name) or name,
      }

      nodes[#nodes + 1] = node
      stack[depth] = node
      prev_depth = depth
    end
  end

  return nodes
end

return M
