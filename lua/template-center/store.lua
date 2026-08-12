local config = require("template-center.config")
local util = require("template-center.util")

local uv = vim.uv or vim.loop

--- The template library. This is the only place in the plugin that touches the
--- filesystem directly.
---
--- Templates are real files, extensions are kept as they are, and directories
--- are categories: `cpp/graph/dinic.cpp`. Side information lives in
--- `.template-center.json` at the root and holds nothing but descriptions and
--- the sidebar's expansion state; the filesystem is always the source of truth,
--- so a missing or broken JSON file has to heal itself.
local M = {}

local META_FILE = ".template-center.json"
local TRASH_DIR = ".trash"
local STASH_DIR = ".tmp-swap"

---@class tc.Entry
---@field id string relative path, e.g. "cpp/graph/dinic.cpp"
---@field name string filename without the extension, e.g. "dinic"
---@field category string containing directory, e.g. "cpp/graph" ("" at the root)
---@field path string absolute path
---@field desc string description, "" when there is none

---@class tc.Node
---@field name string display name, without any path
---@field path string relative path
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

---@param path string absolute path
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

-- ----------------------------------------------------------------- metadata --

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
    util.warn("Could not write " .. META_FILE)
    return
  end
  uv.fs_rename(tmp, path)
end

--- Testing hook: drop the cache so the next read reloads from disk.
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

--- Carry metadata attached to a path (or anything under it) along with a move
--- or a delete.
---@param old string
---@param new string? nil means the entry was deleted
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

-- ------------------------------------------------------------------ reading --

---@param name string
---@return boolean
local function is_hidden(name)
  return vim.startswith(name, ".")
end

--- List the direct children of a directory: directories first, each group
--- sorted by name.
---@param relpath string? "" or nil for the root
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
      -- Anything that is not a directory (symlinks included) counts as a file.
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

--- Every template file, recursively.
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

--- Look a template up by name or by full relative path. When a name is not
--- unique the first match wins, in the order `list` returns.
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

---@param entry tc.Entry|string an entry or a relative path
---@return string[]? lines
---@return string? err
function M.read(entry)
  local path = type(entry) == "string" and M.abspath(entry) or entry.path
  if not uv.fs_stat(path) then
    return nil, "no such file: " .. path
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, "could not read " .. path
  end
  return lines
end

-- ------------------------------------------------------------------ writing --

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

---@param src string absolute path
---@param dst string absolute path
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
    return false, "could not read directory " .. src
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

---@param path string absolute path
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

--- Delete. By default nothing is actually removed; it moves into
--- `<root>/.trash/<timestamp>/` instead, because a single `dd` in the sidebar
--- deletes a file and a slip should not be permanent.
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

    -- Avoid a clash when two files with the same name are deleted in the same
    -- second.
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

--- Move whatever is occupying a target path out of the way (two files swapping
--- names, say) and return where it went. The stash lives inside the library so
--- the rename never crosses devices, and its name starts with a dot so it never
--- shows up in listings.
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

--- Remove the stash if it is empty. Anything left behind stays: it means a move
--- failed, and that data should not be thrown away.
function M.cleanup_stash()
  local path = M.abspath(STASH_DIR)
  if uv.fs_stat(path) then
    uv.fs_rmdir(path) -- fails while non-empty, which is what we want
  end
end

return M
