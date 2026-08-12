local store = require("template-center.store")

--- Compare the edited tree against the one that was drawn and work out which
--- file operations get you from here to there.
---
--- The coordinate systems are the easy thing to confuse:
---   * paths out of `parse` are in **new** coordinates (renames already applied)
---   * paths in `rendered` are in **old** coordinates (where things were drawn)
--- So while applying, only sources need rewriting as earlier moves land;
--- targets are always final.
local M = {}

---@class tc.Op
---@field kind "mkdir"|"create"|"move"|"copy"|"delete"
---@field src string?
---@field dst string?
---@field type "file"|"directory"?

---@param path string
---@return integer
local function depth_of(path)
  local _, n = path:gsub("/", "")
  return n
end

---@param path string
---@param ancestor string
---@return boolean
local function is_under(path, ancestor)
  return path == ancestor or vim.startswith(path, ancestor .. "/")
end

---@param parsed tc.ParsedNode[]
---@param rendered table<integer, tc.Node>
---@param opts { exists: (fun(path: string): boolean)? }?
---@return tc.Op[]? ops
---@return tc.ParseError? err
function M.plan(parsed, rendered, opts)
  local exists = (opts and opts.exists) or store.exists

  local seen = {} ---@type table<integer, boolean>
  local sources = {} ---@type table<string, boolean> what existed when we drew (old coordinates)
  for _, node in pairs(rendered) do
    sources[node.path] = true
  end

  local mkdirs, creates, moves, copies = {}, {}, {}, {}
  local targets = {} ---@type table<string, integer>

  for _, node in ipairs(parsed) do
    if targets[node.path] then
      return nil, { lnum = node.lnum, msg = ("%q appears twice (line %d)"):format(node.path, targets[node.path]) }
    end
    targets[node.path] = node.lnum

    local old = node.id and rendered[node.id] or nil

    if old then
      if old.type ~= node.type then
        local what = old.type == "directory" and "a directory" or "a file"
        return nil, { lnum = node.lnum, msg = ("%q started out as %s and cannot become the other"):format(old.path, what) }
      end

      if seen[node.id] then
        -- The same id showing up twice means the line was duplicated.
        if old.path == node.path then
          return nil, { lnum = node.lnum, msg = ("%q appears twice; give the copy a different name"):format(node.path) }
        end
        copies[#copies + 1] = { kind = "copy", src = old.path, dst = node.path, type = node.type }
      else
        seen[node.id] = true
        if old.path ~= node.path then
          if node.type == "directory" and is_under(node.path, old.path) then
            return nil, { lnum = node.lnum, msg = ("%q cannot be moved inside itself"):format(old.path) }
          end
          moves[#moves + 1] =
            { kind = "move", src = old.path, dst = node.path, type = node.type, lnum = node.lnum }
        end
      end
    elseif node.type == "directory" then
      mkdirs[#mkdirs + 1] = { kind = "mkdir", dst = node.path, type = "directory" }
    else
      creates[#creates + 1] = { kind = "create", dst = node.path, type = "file" }
    end
  end

  -- Any id that is no longer in the buffer was deleted. Children of a collapsed
  -- directory were never drawn, so they are not in `rendered` and can't be
  -- caught up in this.
  local deletes = {}
  for id, node in pairs(rendered) do
    if not seen[id] then
      deletes[#deletes + 1] = { kind = "delete", src = node.path, type = node.type }
    end
  end
  -- When a whole directory goes, its children don't need deleting one by one.
  deletes = vim.tbl_filter(function(op)
    for _, other in ipairs(deletes) do
      if other ~= op and other.type == "directory" and is_under(op.src, other.src) and op.src ~= other.src then
        return false
      end
    end
    return true
  end, deletes)

  -- Something is already sitting at a target, and it isn't a source that is
  -- about to move out of the way. This is the check that catches files hidden
  -- inside a collapsed directory.
  for _, list in ipairs({ mkdirs, creates, moves, copies }) do
    for _, op in ipairs(list) do
      if not sources[op.dst] and exists(op.dst) then
        return nil, {
          lnum = targets[op.dst] or 1,
          msg = ("%q already exists (possibly inside a collapsed directory)"):format(op.dst),
        }
      end
    end
  end

  -- A parent and child trading places (pulling a/b out to sit above a) can't be
  -- done as a sequence of renames; forcing it would stall halfway and leave a
  -- mess. Reject it and ask for two writes instead.
  for _, a in ipairs(moves) do
    for _, b in ipairs(moves) do
      if a ~= b and is_under(b.src, a.src) and is_under(a.dst, b.dst) then
        return nil, {
          lnum = b.lnum or 1,
          msg = ("%q and %q are swapping parent and child; move one, write, then move the other"):format(a.src, b.src),
        }
      end
    end
  end

  table.sort(mkdirs, function(a, b)
    return depth_of(a.dst) < depth_of(b.dst)
  end)
  table.sort(moves, function(a, b)
    return depth_of(a.src) < depth_of(b.src)
  end)
  table.sort(deletes, function(a, b)
    return depth_of(a.src) > depth_of(b.src)
  end)

  local ops = {}
  for _, list in ipairs({ mkdirs, moves, copies, creates, deletes }) do
    vim.list_extend(ops, list)
  end
  return ops
end

---@param ops tc.Op[]
---@return string[]
function M.summary(ops)
  local label = {
    mkdir = "new directory",
    create = "new file",
    move = "move",
    copy = "copy",
    delete = "delete",
  }
  local trash = require("template-center.config").options.explorer.trash

  local out = {}
  for _, op in ipairs(ops) do
    if op.kind == "delete" then
      out[#out + 1] = ("%s  %s%s"):format(label.delete, op.src, trash and "  → .trash/" or "")
    elseif op.kind == "mkdir" or op.kind == "create" then
      out[#out + 1] = ("%s  %s"):format(label[op.kind], op.dst)
    else
      out[#out + 1] = ("%s  %s → %s"):format(label[op.kind], op.src, op.dst)
    end
  end
  return out
end

--- Actually touch the filesystem. Returns the failures (empty means everything
--- went through).
---@param ops tc.Op[]
---@return string[] errors
function M.execute(ops)
  local errors = {}
  local rewrites = {} ---@type { from: string, to: string }[]

  --- Translate an "old coordinates" path into where it actually lives now.
  ---@param path string
  ---@return string
  local function resolve(path)
    for _, r in ipairs(rewrites) do
      if path == r.from then
        path = r.to
      elseif vim.startswith(path, r.from .. "/") then
        path = r.to .. path:sub(#r.from + 1)
      end
    end
    return path
  end

  for _, op in ipairs(ops) do
    local ok, err = true, nil

    if op.kind == "mkdir" then
      ok, err = store.mkdir(op.dst)
    elseif op.kind == "create" then
      ok, err = store.write(op.dst, {})
    elseif op.kind == "move" then
      local src = resolve(op.src)
      -- The target is held by something that hasn't moved out yet (a and b
      -- swapping names, say). Stash the occupant; its own move will fetch it
      -- back out again.
      if src ~= op.dst and store.exists(op.dst) then
        local stashed, serr = store.stash(op.dst)
        if stashed then
          rewrites[#rewrites + 1] = { from = op.dst, to = stashed }
        else
          ok, err = false, serr
        end
      end
      if ok then
        ok, err = store.move(src, op.dst)
        if ok then
          rewrites[#rewrites + 1] = { from = op.src, to = op.dst }
        end
      end
    elseif op.kind == "copy" then
      ok, err = store.copy(resolve(op.src), op.dst)
    elseif op.kind == "delete" then
      ok, err = store.remove(resolve(op.src))
    end

    if not ok then
      errors[#errors + 1] = ("%s %s: %s"):format(op.kind, op.src or op.dst, err or "failed")
    end
  end

  store.cleanup_stash()
  return errors
end

return M
