local store = require("template-center.store")

--- 比對「編輯後的樹」與「畫出來時的樹」，產出要做哪些檔案操作。
---
--- 座標系是這裡最容易搞混的地方：
---   * parse 出來的 path 是**新座標**（已經反映使用者的改名／搬移）
---   * rendered 裡的 path 是**舊座標**（render 當下的實際位置）
--- 所以套用時只有「來源」需要隨著已完成的搬移改寫，目標一律是最終位置。
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
  local sources = {} ---@type table<string, boolean> 畫出來時就存在的東西（舊座標）
  for _, node in pairs(rendered) do
    sources[node.path] = true
  end

  local mkdirs, creates, moves, copies = {}, {}, {}, {}
  local targets = {} ---@type table<string, integer>

  for _, node in ipairs(parsed) do
    if targets[node.path] then
      return nil, { lnum = node.lnum, msg = ("%q 重複了（第 %d 行）"):format(node.path, targets[node.path]) }
    end
    targets[node.path] = node.lnum

    local old = node.id and rendered[node.id] or nil

    if old then
      if old.type ~= node.type then
        local what = old.type == "directory" and "目錄" or "檔案"
        return nil, { lnum = node.lnum, msg = ("%q 原本是%s，不能改成另一種"):format(old.path, what) }
      end

      if seen[node.id] then
        -- 同一個 id 出現第二次 = 使用者複製了那一行。
        if old.path == node.path then
          return nil, { lnum = node.lnum, msg = ("%q 出現兩次，複製的那一份要改個名字"):format(node.path) }
        end
        copies[#copies + 1] = { kind = "copy", src = old.path, dst = node.path, type = node.type }
      else
        seen[node.id] = true
        if old.path ~= node.path then
          if node.type == "directory" and is_under(node.path, old.path) then
            return nil, { lnum = node.lnum, msg = ("不能把 %q 搬進它自己底下"):format(old.path) }
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

  -- 沒有出現在 buffer 裡的 id 就是被刪掉的。收合目錄的子節點從來沒被畫出來，
  -- 自然不在 rendered 裡，所以不會被誤刪。
  local deletes = {}
  for id, node in pairs(rendered) do
    if not seen[id] then
      deletes[#deletes + 1] = { kind = "delete", src = node.path, type = node.type }
    end
  end
  -- 整個目錄被刪時，底下的子項目不用再各刪一次。
  deletes = vim.tbl_filter(function(op)
    for _, other in ipairs(deletes) do
      if other ~= op and other.type == "directory" and is_under(op.src, other.src) and op.src ~= other.src then
        return false
      end
    end
    return true
  end, deletes)

  -- 父子關係整個反轉過來（把 a/b 拉出來當 a 的上層）沒辦法用一連串 rename 做完，
  -- 硬做會卡在中間留下半套結果，所以直接擋下來，請使用者分兩次存檔。
  for _, a in ipairs(moves) do
    for _, b in ipairs(moves) do
      if a ~= b and is_under(b.src, a.src) and is_under(a.dst, b.dst) then
        return nil, {
          lnum = b.lnum or 1,
          msg = ("%q 和 %q 的上下層關係整個反過來了，請先存一次檔搬其中一個，再搬另一個"):format(a.src, b.src),
        }
      end
    end
  end

  -- 目標位置已經有東西，而且那東西不是某個即將讓位的來源 → 中止。
  -- 收合目錄裡「看不見」的檔案就是靠這一關擋下來的。
  for _, list in ipairs({ mkdirs, creates, moves, copies }) do
    for _, op in ipairs(list) do
      if not sources[op.dst] and exists(op.dst) then
        return nil, {
          lnum = targets[op.dst] or 1,
          msg = ("%q 已經存在（可能在收合起來的目錄裡）"):format(op.dst),
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
    mkdir = "新增目錄",
    create = "新增檔案",
    move = "搬移",
    copy = "複製",
    delete = "刪除",
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

--- 真的動檔案系統。回傳失敗訊息的清單（空的代表全部成功）。
---@param ops tc.Op[]
---@return string[] errors
function M.execute(ops)
  local errors = {}
  local rewrites = {} ---@type { from: string, to: string }[]

  --- 把「舊座標」的路徑換算成它現在真正的位置。
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
      -- 目標被另一個「還沒搬走」的項目佔著（例如 a↔b 互換名字），
      -- 先把佔位的搬去暫存區，等它自己那筆 move 再從暫存區搬出來。
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
      errors[#errors + 1] = ("%s %s：%s"):format(op.kind, op.src or op.dst, err or "失敗")
    end
  end

  store.cleanup_stash()
  return errors
end

return M
