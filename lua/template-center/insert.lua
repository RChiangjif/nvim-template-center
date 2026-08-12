local config = require("template-center.config")
local store = require("template-center.store")
local util = require("template-center.util")

--- Put a template into a buffer.
local M = {}

--- Where position = "top" lands: just below the last line matching top_after,
--- or at the very top when nothing matches. Meant for #include-style templates.
---@param bufnr integer
---@return integer row 0-indexed insertion point
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
  -- Limited to the `$1` / `${1:...}` shape so a lone `$` in a shell or LaTeX
  -- template doesn't get mistaken for a placeholder.
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

--- Insert a template.
---@param entry tc.Entry|string an entry, or a template name / relative path
---@param opts { win: integer?, position: "below"|"above"|"top"?, reindent: boolean?, snippet: (boolean|"auto")? }?
---@return boolean ok
function M.insert(entry, opts)
  opts = opts or {}

  if type(entry) == "string" then
    local found = store.find(entry)
    if not found then
      util.error("No such template: " .. entry)
      return false
    end
    entry = found
  end

  local lines, err = store.read(entry)
  if not lines then
    util.error(err or "could not read the template")
    return false
  end
  if #lines == 0 then
    util.warn("Template is empty: " .. entry.id)
    return false
  end

  local cfg = config.options.insert
  local win = util.pick_target_win(opts.win)
  vim.api.nvim_set_current_win(win)

  local bufnr = vim.api.nvim_win_get_buf(win)
  if not vim.bo[bufnr].modifiable then
    util.error("Target buffer is not modifiable")
    return false
  end

  local position = opts.position or cfg.position
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local cur_line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  local blank = not cur_line:match("%S")

  -- On a blank line, insert in place rather than pushing it down and leaving an
  -- empty line behind.
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
    -- vim.snippet.expand starts from the cursor, so lay down one line carrying
    -- the right indentation as a landing spot and let it indent the rest.
    vim.api.nvim_buf_set_lines(bufnr, start_row, end_row, false, { indent })
    vim.api.nvim_win_set_cursor(win, { start_row + 1, #indent })

    if pcall(vim.snippet.expand, text) then
      return true
    end

    -- Bad snippet syntax shouldn't mean the template can't be inserted at all;
    -- fall back to plain text.
    vim.api.nvim_buf_set_lines(bufnr, start_row, start_row + 1, false, {})
    end_row = start_row
  end

  local out = reindent(lines, indent)
  vim.api.nvim_buf_set_lines(bufnr, start_row, end_row, false, out)
  vim.api.nvim_win_set_cursor(win, { start_row + 1, #indent })
  return true
end

--- Used by `:TemplateCenter insert <name>`.
---@param name string
---@param opts table?
---@return boolean
function M.insert_by_name(name, opts)
  return M.insert(name, opts)
end

return M
