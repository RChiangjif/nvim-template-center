local config = require("template-center.config")
local store = require("template-center.store")
local util = require("template-center.util")

--- Save the selected code in a buffer as a template.
local M = {}

--- vim.ui.input is callback-shaped (and may well have been replaced by dressing
--- or snacks), so the questions have to nest rather than run in a straight line.
---@param prompt string
---@param default string?
---@param on_done fun(value: string)
local function ask(prompt, default, on_done)
  vim.ui.input({ prompt = prompt, default = default }, function(value)
    if value == nil then
      util.notify("Cancelled")
      return
    end
    on_done(value)
  end)
end

---@param opts { line1: integer?, line2: integer?, bufnr: integer?, name: string? }
---@return string[]?
local function selected_lines(opts)
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local line1 = opts.line1 or 1
  local line2 = opts.line2 or vim.api.nvim_buf_line_count(bufnr)

  local lines = vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
  lines = util.trim_blank_lines(lines)
  if #lines == 0 then
    util.warn("The selection is empty")
    return nil
  end
  if config.options.capture.dedent then
    lines = util.dedent(lines)
  end
  return lines
end

---@param relpath string
---@param lines string[]
---@param desc string?
local function commit(relpath, lines, desc)
  local ok, err = store.write(relpath, lines)
  if not ok then
    util.error("Could not save: " .. (err or "unknown error"))
    return
  end
  store.set_desc(relpath, desc)
  util.notify(("Saved template %s (%d lines)"):format(relpath, #lines))

  local explorer = package.loaded["template-center.explorer"]
  if explorer and explorer.is_open() then
    explorer.refresh(relpath)
  end
end

---@param relpath string
---@param lines string[]
---@param desc string?
local function commit_checked(relpath, lines, desc)
  if not store.exists(relpath) then
    commit(relpath, lines, desc)
    return
  end

  local choice = vim.fn.confirm(("%s already exists"):format(relpath), "&Overwrite\n&Rename\n&Cancel", 3, "Question")
  if choice == 1 then
    commit(relpath, lines, desc)
  elseif choice == 2 then
    ask("New name or path: ", relpath, function(value)
      local sanitized = util.sanitize(value)
      local valid, verr = util.validate_relpath(sanitized)
      if not valid then
        util.error(verr --[[@as string]])
        return
      end
      commit_checked(sanitized, lines, desc)
    end)
  else
    util.notify("Cancelled")
  end
end

--- Save a template. Without a range this takes the whole buffer.
---@param opts { line1: integer?, line2: integer?, bufnr: integer?, name: string? }?
function M.save(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

  local lines = selected_lines(opts)
  if not lines then
    return
  end

  local ext = util.extension_for(bufnr)
  local cfg = config.options.capture

  ---@param name string already sanitized, may contain "/"
  local function with_name(name)
    local function with_category(category)
      local relpath = category ~= "" and (category .. "/" .. name) or name
      if not relpath:match("%.[%w_]+$") then
        relpath = relpath .. "." .. ext
      end

      local valid, verr = util.validate_relpath(relpath)
      if not valid then
        util.error(verr --[[@as string]])
        return
      end

      if cfg.ask_description then
        ask("Description (optional): ", "", function(desc)
          commit_checked(relpath, lines, vim.trim(desc))
        end)
      else
        commit_checked(relpath, lines, nil)
      end
    end

    -- A name that carries its own path already names the category, so don't ask
    -- for it twice.
    if name:find("/") or not cfg.ask_category then
      with_category("")
    else
      ask("Category (directory, optional): ", vim.bo[bufnr].filetype, function(category)
        with_category(util.sanitize(category))
      end)
    end
  end

  if opts.name and opts.name ~= "" then
    with_name(util.sanitize(opts.name))
  else
    ask("Template name: ", "", function(value)
      local name = util.sanitize(value)
      if name == "" then
        util.warn("Name must not be empty")
        return
      end
      with_name(name)
    end)
  end
end

return M
