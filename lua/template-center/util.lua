local M = {}

local TITLE = "template-center"

---@param msg string
---@param level integer? vim.log.levels, defaults to INFO
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

--- Strip the leading whitespace shared by every non-blank line.
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
        -- Take the common prefix of the two, so mixed tabs and spaces never get
        -- cut in the wrong place.
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

--- Drop blank lines from both ends; a visual selection usually picks up one.
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

--- Validate a single filename (not a path).
---@param name string
---@return boolean ok
---@return string? err
function M.validate_name(name)
  if name == "" then
    return false, "name must not be empty"
  end
  if name == "." or name == ".." then
    return false, ("%q is not a usable name"):format(name)
  end
  if name:find("/") or name:find("\\") then
    return false, ("name must not contain a path separator: %q"):format(name)
  end
  if name:find("^%.") then
    return false, ("name must not start with a dot: %q"):format(name)
  end
  return true
end

--- Validate a relative path, where `/` separates categories.
---@param relpath string
---@return boolean ok
---@return string? err
function M.validate_relpath(relpath)
  if relpath == "" then
    return false, "path must not be empty"
  end
  if relpath:find("^/") or relpath:match("^%a:") then
    return false, "absolute paths are not accepted"
  end
  for part in vim.gsplit(relpath, "/", { plain = true }) do
    local ok, err = M.validate_name(part)
    if not ok then
      return false, err
    end
  end
  return true
end

--- Turn user input into a usable filename: spaces to underscores, dangerous
--- characters dropped.
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

--- Decide which extension a template file should get: copy the source buffer's
--- if it has one, otherwise consult the config table.
---@param bufnr integer
---@return string ext without the dot; "txt" when nothing else fits
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

--- Whether a window can serve as an insert or open target.
---@param win integer?
---@return boolean
function M.is_usable_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false -- floating window
  end
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" or vim.bo[buf].buftype == "acwrite"
end

--- Find an ordinary window to open a file in, creating one if there is none.
---@param prefer integer? window to use if it still works
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
