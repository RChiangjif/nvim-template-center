local config = require("template-center.config")
local store = require("template-center.store")
local util = require("template-center.util")

--- 把 buffer 裡選取的程式碼存成模板。
local M = {}

--- vim.ui.input 是 callback 形式的（而且可能被 dressing / snacks 換掉），
--- 所以問答只能一層層串下去，不能寫成直線流程。
---@param prompt string
---@param default string?
---@param on_done fun(value: string)
local function ask(prompt, default, on_done)
  vim.ui.input({ prompt = prompt, default = default }, function(value)
    if value == nil then
      util.notify("已取消")
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
    util.warn("選取範圍是空的")
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
    util.error("儲存失敗：" .. (err or "未知錯誤"))
    return
  end
  store.set_desc(relpath, desc)
  util.notify(("已存入模板 %s（%d 行）"):format(relpath, #lines))

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

  local choice = vim.fn.confirm(("%s 已存在"):format(relpath), "覆寫(&O)\n改名(&R)\n取消(&C)", 3, "Question")
  if choice == 1 then
    commit(relpath, lines, desc)
  elseif choice == 2 then
    ask("新的名稱/路徑：", relpath, function(value)
      local sanitized = util.sanitize(value)
      local valid, verr = util.validate_relpath(sanitized)
      if not valid then
        util.error(verr --[[@as string]])
        return
      end
      commit_checked(sanitized, lines, desc)
    end)
  else
    util.notify("已取消")
  end
end

--- 存模板。無 range 時預設整個 buffer。
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

  ---@param name string 已 sanitize，可能含 "/"
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
        ask("說明（可留空）：", "", function(desc)
          commit_checked(relpath, lines, vim.trim(desc))
        end)
      else
        commit_checked(relpath, lines, nil)
      end
    end

    -- 名稱自己帶了路徑就當作已經指定分類，不再多問一次。
    if name:find("/") or not cfg.ask_category then
      with_category("")
    else
      ask("分類（目錄，可留空）：", vim.bo[bufnr].filetype, function(category)
        with_category(util.sanitize(category))
      end)
    end
  end

  if opts.name and opts.name ~= "" then
    with_name(util.sanitize(opts.name))
  else
    ask("模板名稱：", "", function(value)
      local name = util.sanitize(value)
      if name == "" then
        util.warn("名稱不可為空")
        return
      end
      with_name(name)
    end)
  end
end

return M
