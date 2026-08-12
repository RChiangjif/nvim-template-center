local config = require("template-center.config")
local util = require("template-center.util")

local uv = vim.uv or vim.loop

--- 模板庫。這是整個 plugin 唯一直接碰檔案系統的地方。
---
--- 模板就是真實檔案，副檔名保留原樣，目錄即分類：`cpp/graph/dinic.cpp`。
--- 附屬資訊放在 root 下的 `.template-center.json`，只存說明文字與側邊欄展開狀態；
--- 檔案系統永遠是真相來源，json 壞掉或缺欄位都要能自我修復。
local M = {}

local META_FILE = ".template-center.json"
local TRASH_DIR = ".trash"
local STASH_DIR = ".tmp-swap"

---@class tc.Entry
---@field id string 相對路徑，例如 "cpp/graph/dinic.cpp"
---@field name string 不含副檔名的檔名，例如 "dinic"
---@field category string 所在目錄，例如 "cpp/graph"（root 為 ""）
---@field path string 絕對路徑
---@field desc string 說明，沒有則為 ""

---@class tc.Node
---@field name string 顯示名稱（不含路徑）
---@field path string 相對路徑
---@field type "file"|"directory"

---@return string
function M.root()
  return config.options.dir
end

---@param relpath string?
---@return string
function M.abspath(relpath)
  if not relpath or relpath == "" then
    return M.root()
  end
  return vim.fs.joinpath(M.root(), relpath)
end

---@param path string 絕對路徑
---@return "file"|"directory"|nil
local function stat_type(path)
  local st = uv.fs_stat(path)
  if not st then
    return nil
  end
  return st.type == "directory" and "directory" or "file"
end

---@param relpath string
---@return boolean
function M.exists(relpath)
  return stat_type(M.abspath(relpath)) ~= nil
end

function M.ensure()
  vim.fn.mkdir(M.root(), "p")
end

-- ---------------------------------------------------------------- metadata --

---@type { desc: table<string, string>, expanded: table<string, boolean> }?
local meta = nil

---@return { desc: table<string, string>, expanded: table<string, boolean> }
local function load_meta()
  if meta then
    return meta
  end
  meta = { desc = {}, expanded = {} }

  local path = M.abspath(META_FILE)
  if not uv.fs_stat(path) then
    return meta
  end

  local ok, content = pcall(vim.fn.readfile, path)
  if not ok or #content == 0 then
    return meta
  end

  local decoded
  ok, decoded = pcall(vim.json.decode, table.concat(content, "\n"))
  if ok and type(decoded) == "table" then
    if type(decoded.desc) == "table" then
      meta.desc = decoded.desc
    end
    if type(decoded.expanded) == "table" then
      meta.expanded = decoded.expanded
    end
  end
  return meta
end

local function save_meta()
  if not meta then
    return
  end
  M.ensure()
  local path = M.abspath(META_FILE)
  local tmp = path .. ".tmp"
  local encoded = vim.json.encode(meta)
  local ok = pcall(vim.fn.writefile, vim.split(encoded, "\n"), tmp)
  if not ok then
    util.warn("無法寫入 " .. META_FILE)
    return
  end
  uv.fs_rename(tmp, path)
end

--- 測試用：丟掉快取，下次讀取重新載入。
function M.reload_meta()
  meta = nil
end

---@param relpath string
---@return string
function M.get_desc(relpath)
  return load_meta().desc[relpath] or ""
end

---@param relpath string
---@param desc string?
function M.set_desc(relpath, desc)
  local m = load_meta()
  m.desc[relpath] = (desc and desc ~= "") and desc or nil
  save_meta()
end

---@return table<string, boolean>
function M.expanded()
  return load_meta().expanded
end

---@param relpath string
---@param value boolean
function M.set_expanded(relpath, value)
  local m = load_meta()
  m.expanded[relpath] = value or nil
  save_meta()
end

--- 搬移／刪除檔案時，把 meta 裡掛在該路徑（或其子路徑）上的資料跟著搬。
---@param old string
---@param new string? nil 表示刪除
local function migrate_meta(old, new)
  local m = load_meta()
  local prefix = old .. "/"

  for _, field in ipairs({ "desc", "expanded" }) do
    local tbl = m[field]
    local moved = {}
    for key, value in pairs(tbl) do
      if key == old or vim.startswith(key, prefix) then
        tbl[key] = nil
        if new then
          moved[new .. key:sub(#old + 1)] = value
        end
      end
    end
    for key, value in pairs(moved) do
      tbl[key] = value
    end
  end

  save_meta()
end

-- ------------------------------------------------------------------- 讀取 --

---@param name string
---@return boolean
local function is_hidden(name)
  return vim.startswith(name, ".")
end

--- 列出某個目錄的直接子項目，目錄排前面，各自依名稱排序。
---@param relpath string? "" 或 nil 表示 root
---@return tc.Node[]
function M.children(relpath)
  relpath = relpath or ""
  local dir = M.abspath(relpath)
  local nodes = {} ---@type tc.Node[]

  local handle = uv.fs_scandir(dir)
  if not handle then
    return nodes
  end

  while true do
    local name, type_ = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if not is_hidden(name) then
      -- symlink 等其他型別一律當檔案處理。
      local kind = type_ == "directory" and "directory" or "file"
      if type_ == "link" then
        kind = stat_type(vim.fs.joinpath(dir, name)) or "file"
      end
      nodes[#nodes + 1] = {
        name = name,
        path = relpath == "" and name or (relpath .. "/" .. name),
        type = kind,
      }
    end
  end

  table.sort(nodes, function(a, b)
    if (a.type == "directory") ~= (b.type == "directory") then
      return a.type == "directory"
    end
    return a.name:lower() < b.name:lower()
  end)

  return nodes
end

---@param relpath string
---@return tc.Entry
function M.entry_of(relpath)
  local category = vim.fs.dirname(relpath)
  if category == "." or category == relpath then
    category = ""
  end
  local filename = vim.fs.basename(relpath)
  return {
    id = relpath,
    name = filename:gsub("%.[%w_]+$", ""),
    category = category,
    path = M.abspath(relpath),
    desc = M.get_desc(relpath),
  }
end

--- 遞迴列出所有模板檔案。
---@return tc.Entry[]
function M.list()
  M.ensure()
  local entries = {} ---@type tc.Entry[]

  for relpath, type_ in vim.fs.dir(M.root(), { depth = 32 }) do
    local hidden = false
    for part in vim.gsplit(relpath, "/", { plain = true }) do
      if is_hidden(part) then
        hidden = true
        break
      end
    end
    if not hidden and type_ ~= "directory" then
      entries[#entries + 1] = M.entry_of(relpath)
    end
  end

  table.sort(entries, function(a, b)
    if a.name:lower() ~= b.name:lower() then
      return a.name:lower() < b.name:lower()
    end
    return a.id < b.id
  end)

  return entries
end

--- 依名稱或完整相對路徑找模板。名稱不唯一時回傳第一個（list 的排序）。
---@param query string
---@return tc.Entry?
function M.find(query)
  local entries = M.list()
  for _, entry in ipairs(entries) do
    if entry.id == query then
      return entry
    end
  end
  for _, entry in ipairs(entries) do
    if entry.name == query then
      return entry
    end
  end
  return nil
end

---@param entry tc.Entry|string entry 或相對路徑
---@return string[]? lines
---@return string? err
function M.read(entry)
  local path = type(entry) == "string" and M.abspath(entry) or entry.path
  if not uv.fs_stat(path) then
    return nil, "檔案不存在：" .. path
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, "讀取失敗：" .. path
  end
  return lines
end

-- ------------------------------------------------------------------- 寫入 --

---@param relpath string
---@return boolean ok
---@return string? err
function M.mkdir(relpath)
  local ok, err = pcall(vim.fn.mkdir, M.abspath(relpath), "p")
  if not ok then
    return false, tostring(err)
  end
  return true
end

---@param relpath string
---@param lines string[]
---@return boolean ok
---@return string? err
function M.write(relpath, lines)
  local valid, verr = util.validate_relpath(relpath)
  if not valid then
    return false, verr
  end

  local parent = vim.fs.dirname(relpath)
  if parent and parent ~= "." and parent ~= relpath then
    local ok, err = M.mkdir(parent)
    if not ok then
      return false, err
    end
  else
    M.ensure()
  end

  local ok, err = pcall(vim.fn.writefile, lines, M.abspath(relpath))
  if not ok then
    return false, tostring(err)
  end
  return true
end

---@param old string
---@param new string
---@return boolean ok
---@return string? err
function M.move(old, new)
  local valid, verr = util.validate_relpath(new)
  if not valid then
    return false, verr
  end

  local parent = vim.fs.dirname(new)
  if parent and parent ~= "." and parent ~= new then
    M.mkdir(parent)
  end

  local ok, err = uv.fs_rename(M.abspath(old), M.abspath(new))
  if not ok then
    return false, tostring(err)
  end
  migrate_meta(old, new)
  return true
end

---@param src string 絕對路徑
---@param dst string 絕對路徑
---@return boolean ok
---@return string? err
local function copy_recursive(src, dst)
  local type_ = stat_type(src)
  if type_ == "file" then
    local ok, err = uv.fs_copyfile(src, dst)
    if not ok then
      return false, tostring(err)
    end
    return true
  end

  vim.fn.mkdir(dst, "p")
  local handle = uv.fs_scandir(src)
  if not handle then
    return false, "無法讀取目錄：" .. src
  end
  while true do
    local name = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    local ok, err = copy_recursive(vim.fs.joinpath(src, name), vim.fs.joinpath(dst, name))
    if not ok then
      return false, err
    end
  end
  return true
end

---@param old string
---@param new string
---@return boolean ok
---@return string? err
function M.copy(old, new)
  local valid, verr = util.validate_relpath(new)
  if not valid then
    return false, verr
  end

  local parent = vim.fs.dirname(new)
  if parent and parent ~= "." and parent ~= new then
    M.mkdir(parent)
  end

  local ok, err = copy_recursive(M.abspath(old), M.abspath(new))
  if not ok then
    return false, err
  end

  local desc = M.get_desc(old)
  if desc ~= "" then
    M.set_desc(new, desc)
  end
  return true
end

---@param path string 絕對路徑
---@return boolean ok
---@return string? err
local function remove_recursive(path)
  local type_ = stat_type(path)
  if type_ == nil then
    return true
  end
  if type_ == "file" then
    local ok, err = uv.fs_unlink(path)
    return ok and true or false, err and tostring(err) or nil
  end

  local handle = uv.fs_scandir(path)
  if handle then
    while true do
      local name = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      local ok, err = remove_recursive(vim.fs.joinpath(path, name))
      if not ok then
        return false, err
      end
    end
  end
  local ok, err = uv.fs_rmdir(path)
  return ok and true or false, err and tostring(err) or nil
end

--- 刪除。預設不是真的刪掉，而是搬進 `<root>/.trash/<timestamp>/`，
--- 因為側邊欄一個 `dd` 就能刪東西，手滑的代價不該是永久性的。
---@param relpath string
---@return boolean ok
---@return string? err
function M.remove(relpath)
  local abs = M.abspath(relpath)
  if not uv.fs_stat(abs) then
    return true
  end

  if config.options.explorer.trash then
    local stamp = os.date("%Y%m%d-%H%M%S")
    local dest = vim.fs.joinpath(M.root(), TRASH_DIR, stamp, relpath)
    local parent = vim.fs.dirname(dest)
    vim.fn.mkdir(parent, "p")

    -- 同一秒內刪掉同名檔案時避開撞名。
    local candidate, n = dest, 1
    while uv.fs_stat(candidate) do
      candidate = ("%s.%d"):format(dest, n)
      n = n + 1
    end

    local ok, err = uv.fs_rename(abs, candidate)
    if not ok then
      return false, tostring(err)
    end
    migrate_meta(relpath, nil)
    return true
  end

  local ok, err = remove_recursive(abs)
  if not ok then
    return false, err
  end
  migrate_meta(relpath, nil)
  return true
end

---@return string
function M.trash_dir()
  return vim.fs.joinpath(M.root(), TRASH_DIR)
end

--- 把佔住目標位置的東西暫時挪開（例如 a↔b 互換名字），回傳它的暫存相對路徑。
--- 暫存區在模板庫內部，才不會跨裝置搬檔；名稱以 `.` 開頭所以不會被列出來。
---@param relpath string
---@return string? stashed
---@return string? err
function M.stash(relpath)
  local stash_root = M.abspath(STASH_DIR)
  vim.fn.mkdir(stash_root, "p")

  local n, rel = 0, nil
  repeat
    n = n + 1
    rel = ("%s/%d"):format(STASH_DIR, n)
  until not uv.fs_stat(M.abspath(rel))

  local ok, err = uv.fs_rename(M.abspath(relpath), M.abspath(rel))
  if not ok then
    return nil, tostring(err)
  end
  migrate_meta(relpath, rel)
  return rel
end

--- 清掉空的暫存區；還有東西留著就保留（代表某個 move 失敗了，別把資料弄丟）。
function M.cleanup_stash()
  local path = M.abspath(STASH_DIR)
  if uv.fs_stat(path) then
    uv.fs_rmdir(path) -- 非空時會失敗，正是我們要的
  end
end

return M
