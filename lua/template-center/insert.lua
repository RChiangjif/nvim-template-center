local config = require("template-center.config")
local store = require("template-center.store")
local util = require("template-center.util")

--- 把模板插進 buffer。
local M = {}

--- position = "top" 時的落點：最後一行符合 top_after 的下面，
--- 沒有任何一行符合就插在檔首。（給 #include 這類前置模板用。）
---@param bufnr integer
---@return integer row 0-indexed 的插入位置
local function top_row(bufnr)
  local patterns = config.options.insert.top_after or {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local last = 0
  for i, line in ipairs(lines) do
    for _, pattern in ipairs(patterns) do
      if line:match(pattern) then
        last = i
        break
      end
    end
  end
  return last
end

---@param text string
---@return boolean
local function looks_like_snippet(text)
  -- 收斂到 `$1` / `${1:...}` 這種形狀，避免 shell、LaTeX 裡單純的 `$` 被誤判。
  return text:find("%$%d") ~= nil or text:find("%${%d") ~= nil
end

---@param lines string[]
---@param indent string
---@return string[]
local function reindent(lines, indent)
  if indent == "" then
    return lines
  end
  local out = {}
  for i, line in ipairs(lines) do
    out[i] = line:match("%S") and (indent .. line) or line
  end
  return out
end

--- 插入模板。
---@param entry tc.Entry|string entry 或模板名稱／相對路徑
---@param opts { win: integer?, position: "below"|"above"|"top"?, reindent: boolean?, snippet: (boolean|"auto")? }?
---@return boolean ok
function M.insert(entry, opts)
  opts = opts or {}

  if type(entry) == "string" then
    local found = store.find(entry)
    if not found then
      util.error("找不到模板：" .. entry)
      return false
    end
    entry = found
  end

  local lines, err = store.read(entry)
  if not lines then
    util.error(err or "讀取失敗")
    return false
  end
  if #lines == 0 then
    util.warn("模板是空的：" .. entry.id)
    return false
  end

  local cfg = config.options.insert
  local win = util.pick_target_win(opts.win)
  vim.api.nvim_set_current_win(win)

  local bufnr = vim.api.nvim_win_get_buf(win)
  if not vim.bo[bufnr].modifiable then
    util.error("目標 buffer 不可修改")
    return false
  end

  local position = opts.position or cfg.position
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local cur_line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  local blank = not cur_line:match("%S")

  -- 游標停在空行時直接就地插入，不要再往下推一行留個空行。
  local start_row, end_row
  if position == "top" then
    start_row = top_row(bufnr)
    end_row = start_row
  elseif position == "above" then
    start_row = row - 1
    end_row = blank and row or start_row
  else
    start_row = blank and (row - 1) or row
    end_row = blank and row or start_row
  end

  local indent = ""
  if opts.reindent ~= false and cfg.reindent and position ~= "top" then
    indent = cur_line:match("^[ \t]*") or ""
  end

  local snippet_mode = opts.snippet
  if snippet_mode == nil then
    snippet_mode = cfg.snippet
  end
  local text = table.concat(lines, "\n")
  local as_snippet = snippet_mode == true or (snippet_mode == "auto" and looks_like_snippet(text))

  if as_snippet and vim.snippet and vim.snippet.expand then
    -- vim.snippet.expand 是從游標處展開的，所以先鋪一行帶好縮排的空行當落點，
    -- 後續行的縮排交給它自己處理。
    vim.api.nvim_buf_set_lines(bufnr, start_row, end_row, false, { indent })
    vim.api.nvim_win_set_cursor(win, { start_row + 1, #indent })

    if pcall(vim.snippet.expand, text) then
      return true
    end

    -- snippet 語法有問題就退回純文字插入，不要讓模板整個插不進去。
    vim.api.nvim_buf_set_lines(bufnr, start_row, start_row + 1, false, {})
    end_row = start_row
  end

  local out = reindent(lines, indent)
  vim.api.nvim_buf_set_lines(bufnr, start_row, end_row, false, out)
  vim.api.nvim_win_set_cursor(win, { start_row + 1, #indent })
  return true
end

--- 給 `:TemplateCenter insert <name>` 用。
---@param name string
---@param opts table?
---@return boolean
function M.insert_by_name(name, opts)
  return M.insert(name, opts)
end

return M
