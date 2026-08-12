local config = require("template-center.config")
local store = require("template-center.store")
local util = require("template-center.util")

--- 搜尋視窗。telescope 有裝就用 telescope，沒有就退回 `vim.ui.select`
--- —— 而 dressing / snacks / fzf-lua 這些本來就會接管 `vim.ui.select`，
--- 所以不需要為它們各寫一份 adapter。
local M = {}

---@class tc.PickerContext
---@field win integer 呼叫 picker 當下的視窗，插入／開檔都往這裡送
---@field prompt string
---@field on_select fun(entry: tc.Entry, ctx: tc.PickerContext)

M.actions = {}

---@param entry tc.Entry
---@param ctx tc.PickerContext
function M.actions.insert(entry, ctx)
  require("template-center.insert").insert(entry, { win = ctx.win })
end

---@param entry tc.Entry
---@param ctx tc.PickerContext
function M.actions.edit(entry, ctx)
  local win = util.pick_target_win(ctx.win)
  vim.api.nvim_set_current_win(win)
  vim.cmd.edit(vim.fn.fnameescape(entry.path))
end

---@param entry tc.Entry
function M.actions.yank(entry)
  local lines = store.read(entry)
  if not lines then
    return
  end
  local text = table.concat(lines, "\n")
  vim.fn.setreg('"', text, "l")
  vim.fn.setreg("0", text, "l")
  util.notify(("已複製 %s（%d 行），p 貼上"):format(entry.id, #lines))
end

---@param entry tc.Entry
function M.actions.reveal(entry)
  require("template-center.explorer").open({ focus = true, reveal = entry.id })
end

---@return table? backend
local function backend()
  local choice = config.options.picker

  if choice ~= "select" then
    local ok, telescope = pcall(require, "template-center.picker.telescope")
    if ok and telescope.available() then
      return telescope
    end
    if choice == "telescope" then
      util.warn("找不到 telescope，改用 vim.ui.select")
    end
  end

  return require("template-center.picker.select")
end

---@param opts { prompt: string?, win: integer?, on_select: fun(entry: tc.Entry, ctx: tc.PickerContext)? }?
function M.pick(opts)
  opts = opts or {}

  local entries = store.list()
  if #entries == 0 then
    util.warn(("模板庫是空的（%s）。先用 :TemplateCenter save 存一個吧"):format(store.root()))
    return
  end

  ---@type tc.PickerContext
  local ctx = {
    win = opts.win or vim.api.nvim_get_current_win(),
    prompt = opts.prompt or "模板",
    on_select = opts.on_select or M.actions.insert,
  }

  backend().pick(entries, ctx)
end

--- 選了就插入目前的 buffer。
---@param opts table?
function M.find(opts)
  opts = vim.tbl_extend("force", { prompt = "插入模板", on_select = M.actions.insert }, opts or {})
  M.pick(opts)
end

--- 選了就開檔編輯模板本身。
---@param opts table?
function M.open(opts)
  opts = vim.tbl_extend("force", { prompt = "編輯模板", on_select = M.actions.edit }, opts or {})
  M.pick(opts)
end

return M
