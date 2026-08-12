local store = require("template-center.store")

--- 把模板庫畫成 buffer 的行。
---
--- 行的格式是 `/<id> <縮排><名稱>`，`/<id> ` 由 syntax/templatecenter.vim 隱藏起來
--- （oil.nvim 的做法）。id 只在單次 render 內有效，每次重畫都重新發號。
--- 收合的目錄不展開子節點 —— 沒被畫出來的東西也就不會進 diff，這是「收合的目錄
--- 不會被誤刪」的根本原因。
local M = {}

---@class tc.RenderResult
---@field lines string[]
---@field rendered table<integer, tc.Node> id → 節點（節點的 path 是「舊座標」）
---@field line_of table<string, integer> 相對路徑 → 行號（1-indexed）

---@param opts { expanded: table<string, boolean>, indent: integer }
---@return tc.RenderResult
function M.build(opts)
  local unit = string.rep(" ", opts.indent)
  local expanded = opts.expanded or {}

  local lines = {} ---@type string[]
  local rendered = {} ---@type table<integer, tc.Node>
  local line_of = {} ---@type table<string, integer>
  local id = 0

  local function walk(dir, depth)
    for _, node in ipairs(store.children(dir)) do
      id = id + 1
      local display = node.name .. (node.type == "directory" and "/" or "")
      lines[#lines + 1] = ("/%d %s%s"):format(id, unit:rep(depth), display)
      rendered[id] = node
      line_of[node.path] = #lines

      if node.type == "directory" and expanded[node.path] then
        walk(node.path, depth + 1)
      end
    end
  end

  walk("", 0)

  return { lines = lines, rendered = rendered, line_of = line_of }
end

--- 取出某一行的 id。
---@param line string
---@return integer?
function M.id_of(line)
  local id = line:match("^/(%d+)%s")
  return id and tonumber(id) or nil
end

return M
