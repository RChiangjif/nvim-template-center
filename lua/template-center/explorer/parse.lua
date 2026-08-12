local util = require("template-center.util")

--- Read the edited buffer back into a tree. Pure: it never touches the
--- filesystem.
---
--- The structure comes from the **indentation**, not from the ids — pushing a
--- line one level to the right is how you move it into the directory above.
--- Any failed check rejects the whole batch (never half of it) and reports the
--- line number.
local M = {}

---@class tc.ParsedNode
---@field id integer? absent means this line is new
---@field name string
---@field type "file"|"directory"
---@field depth integer
---@field lnum integer
---@field path string relative path in the new coordinates

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
  local stack = {} ---@type table<integer, tc.ParsedNode> depth → last node seen at that depth
  local taken = {} ---@type table<string, integer> "parent path\0name" → line number
  local prev_depth = -1

  for lnum, line in ipairs(lines) do
    if line:match("%S") then -- blank lines are ignored
      local id, rest = line:match("^/(%d+)%s(.*)$")
      if not id then
        rest = line
      end

      local ws, body = rest:match("^([ \t]*)(.*)$")

      -- A tab counts as a whole level, so indentation still lines up for people
      -- without 'expandtab'.
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
        return nil, { lnum = lnum, msg = "indentation jumps more than one level" }
      end

      local parent = depth > 0 and stack[depth - 1] or nil
      if depth > 0 then
        if not parent then
          return nil, { lnum = lnum, msg = "no directory at the level above" }
        end
        if parent.type ~= "directory" then
          return nil, { lnum = lnum, msg = ("%q is not a directory, nothing can go inside it"):format(parent.name) }
        end
      end

      local parent_path = parent and parent.path or ""
      local key = parent_path .. "\0" .. name
      if taken[key] then
        return nil, { lnum = lnum, msg = ("%q already exists at this level (line %d)"):format(name, taken[key]) }
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
