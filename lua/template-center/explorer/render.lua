local store = require("template-center.store")

--- Draw the library as buffer lines.
---
--- Every line reads `/<id> <indent><name>`, and `/<id> ` is hidden by
--- syntax/templatecenter.vim (the trick oil.nvim uses). Ids are only meaningful
--- within a single render and are handed out afresh on every redraw.
---
--- Collapsed directories are not descended into. What never gets drawn never
--- enters the diff either, which is the whole reason a collapsed directory
--- cannot be deleted by accident.
local M = {}

---@class tc.RenderResult
---@field lines string[]
---@field rendered table<integer, tc.Node> id → node (whose path is in "old" coordinates)
---@field line_of table<string, integer> relative path → line number (1-indexed)

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

--- Pull the id out of a line.
---@param line string
---@return integer?
function M.id_of(line)
  local id = line:match("^/(%d+)%s")
  return id and tonumber(id) or nil
end

return M
